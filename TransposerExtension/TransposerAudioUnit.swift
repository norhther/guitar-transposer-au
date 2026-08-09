import AVFoundation
import AudioToolbox

public class TransposerAudioUnit: AUAudioUnit {
    private var bridge: SignalsmithBridge!
    private var inputBus: AUAudioUnitBus!
    private var outputBus: AUAudioUnitBus!
    private var _inputBusArray: AUAudioUnitBusArray!
    private var _outputBusArray: AUAudioUnitBusArray!

    private var scratchInput: [[Float]] = []
    private var scratchInputPointers: [UnsafePointer<Float>?] = []
    private var outputPointers: [UnsafeMutablePointer<Float>?] = []

    private let semitonesParam: AUParameter
    private let latencyModeParam: AUParameter
    private let paramTree: AUParameterTree

    public override init(componentDescription: AudioComponentDescription,
                          options: AudioComponentInstantiationOptions = []) throws {
        semitonesParam = AUParameterTree.createParameter(
            withIdentifier: "semitones",
            name: "Semitones",
            address: TransposerParameterAddress.semitones.rawValue,
            min: -12, max: 12,
            unit: .indexed,
            unitName: nil,
            flags: [.flag_IsWritable, .flag_IsReadable],
            valueStrings: nil,
            dependentParameters: nil)
        semitonesParam.value = 0

        latencyModeParam = AUParameterTree.createParameter(
            withIdentifier: "latencyMode",
            name: "Latency Mode",
            address: TransposerParameterAddress.latencyMode.rawValue,
            min: 0, max: 2,
            unit: .indexed,
            unitName: nil,
            flags: [.flag_IsWritable, .flag_IsReadable],
            valueStrings: ["Fast", "Balanced", "Quality"],
            dependentParameters: nil)
        latencyModeParam.value = 1

        paramTree = AUParameterTree.createTree(withChildren: [semitonesParam, latencyModeParam])

        try super.init(componentDescription: componentDescription, options: options)

        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        inputBus = try AUAudioUnitBus(format: format)
        outputBus = try AUAudioUnitBus(format: format)
        _inputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [inputBus])
        _outputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])

        paramTree.implementorValueObserver = { [weak self] param, value in
            guard let self = self, let address = TransposerParameterAddress(rawValue: param.address) else { return }
            switch address {
            case .semitones:
                self.bridge?.setSemitones(Float(value))
            case .latencyMode:
                if let mode = TransposerLatencyMode(rawValue: Int(value)) {
                    self.bridge?.request(mode)
                }
            }
        }
        paramTree.implementorValueProvider = { param in
            param.value
        }
    }

    public override var parameterTree: AUParameterTree? {
        get { paramTree }
        set { }
    }

    public override var inputBusses: AUAudioUnitBusArray { _inputBusArray }
    public override var outputBusses: AUAudioUnitBusArray { _outputBusArray }

    public override var latency: TimeInterval {
        guard let bridge = bridge, outputBus.format.sampleRate > 0 else { return 0 }
        return Double(bridge.appliedLatencySamples()) / outputBus.format.sampleRate
    }

    /// Thread-safe from any thread (backed by the bridge's atomics). Polled by the UI timer
    /// in TransposerViewController (Task 7) — never called from the render thread itself.
    public func currentPeaks() -> (input: Float, output: Float) {
        guard let bridge = bridge else { return (0, 0) }
        return (bridge.inputPeak(), bridge.outputPeak())
    }

    public override func allocateRenderResources() throws {
        try super.allocateRenderResources()
        let sampleRate = outputBus.format.sampleRate
        let channelCount = Int(outputBus.format.channelCount)
        bridge = SignalsmithBridge(sampleRate: sampleRate, channelCount: channelCount)
        bridge.setSemitones(Float(semitonesParam.value))
        if let mode = TransposerLatencyMode(rawValue: Int(latencyModeParam.value)) {
            bridge.request(mode)
        }

        let maxFrames = Int(maximumFramesToRender)
        scratchInput = Array(repeating: [Float](repeating: 0, count: maxFrames), count: channelCount)
        scratchInputPointers = Array(repeating: nil, count: channelCount)
        outputPointers = Array(repeating: nil, count: channelCount)
    }

    public override func deallocateRenderResources() {
        bridge = nil
        scratchInput = []
        scratchInputPointers = []
        outputPointers = []
        super.deallocateRenderResources()
    }

    public override var internalRenderBlock: AUInternalRenderBlock {
        let bridge = self.bridge!
        return { [weak self] actionFlags, timestamp, frameCount, outputBusNumber, outputData, realtimeEventListHead, pullInputBlock in
            guard let self = self, let pullInputBlock = pullInputBlock else { return kAudioUnitErr_NoConnection }

            var inputFlags = AudioUnitRenderActionFlags()
            let status = pullInputBlock(&inputFlags, timestamp, frameCount, 0, outputData)
            if status != noErr { return status }

            let bufferList = UnsafeMutableAudioBufferListPointer(outputData)
            let channelCount = bufferList.count
            let frames = Int(frameCount)

            // Write into the persistent instance-level pointer arrays in place (index
            // assignment, not append) so no array backing store is allocated per render call.
            for i in 0..<channelCount {
                let outPtr = bufferList[i].mData!.assumingMemoryBound(to: Float.self)
                self.scratchInput[i].withUnsafeMutableBufferPointer { scratch in
                    scratch.baseAddress!.update(from: outPtr, count: frames)
                    self.scratchInputPointers[i] = UnsafePointer(scratch.baseAddress!)
                }
                self.outputPointers[i] = outPtr
            }

            self.scratchInputPointers.withUnsafeMutableBufferPointer { inBuf in
                self.outputPointers.withUnsafeMutableBufferPointer { outBuf in
                    bridge.processInputs(inBuf.baseAddress!, outputs: outBuf.baseAddress!, frameCount: frameCount)
                }
            }
            return noErr
        }
    }
}
