import AVFoundation
import AudioToolbox

/// Small reference-type box so the render block can read the live bypass state via a
/// strongly-captured local reference (no `self`, no weak-load lock) — see `internalRenderBlock`.
private final class BypassBox {
    var isBypassed: Bool = false
}

/// Everything the render block touches, behind one reference the block captures once.
///
/// `internalRenderBlock` can be fetched by a host *before* `allocateRenderResources()`
/// runs, and hosts cache the block they got. Capturing `bridge` and the scratch buffers
/// directly in the closure therefore freezes whatever state existed at fetch time —
/// usually nil/empty — and the unit never renders. Going through this box means the
/// closure sees whatever `allocateRenderResources()` later installs.
private final class RenderState {
    var bridge: SignalsmithBridge?
    var scratchInput: [[Float]] = []
    var scratchInputPointers: [UnsafePointer<Float>?] = []
    var outputPointers: [UnsafeMutablePointer<Float>?] = []
    var outputScratch: [[Float]] = []
}

public class TransposerAudioUnit: AUAudioUnit {
    private var inputBus: AUAudioUnitBus!
    private var outputBus: AUAudioUnitBus!
    private var _inputBusArray: AUAudioUnitBusArray!
    private var _outputBusArray: AUAudioUnitBusArray!

    private let state = RenderState()
    private var bridge: SignalsmithBridge? { state.bridge }

    private let bypassBox = BypassBox()

    private let semitonesParam: AUParameter
    private let latencyModeParam: AUParameter
    private let formantSemitonesParam: AUParameter
    private let formantCompensateParam: AUParameter
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

        formantSemitonesParam = AUParameterTree.createParameter(
            withIdentifier: "formantSemitones",
            name: "Formant",
            address: TransposerParameterAddress.formantSemitones.rawValue,
            min: -12, max: 12,
            unit: .indexed,
            unitName: nil,
            flags: [.flag_IsWritable, .flag_IsReadable],
            valueStrings: nil,
            dependentParameters: nil)
        formantSemitonesParam.value = 0

        formantCompensateParam = AUParameterTree.createParameter(
            withIdentifier: "formantCompensate",
            name: "Compensate Formant",
            address: TransposerParameterAddress.formantCompensate.rawValue,
            min: 0, max: 1,
            unit: .boolean,
            unitName: nil,
            flags: [.flag_IsWritable, .flag_IsReadable],
            valueStrings: nil,
            dependentParameters: nil)
        formantCompensateParam.value = 0

        paramTree = AUParameterTree.createTree(withChildren: [semitonesParam, latencyModeParam, formantSemitonesParam, formantCompensateParam])

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
                    // Hosts cache `latency` for PDC; tell them to re-query it. The bridge
                    // applies the new mode asynchronously on the render thread's next call,
                    // so this is a best-effort signal, not a guarantee of an immediately
                    // up-to-date value.
                    self.willChangeValue(forKey: "latency")
                    self.didChangeValue(forKey: "latency")
                }
            case .formantSemitones:
                self.bridge?.setFormantSemitones(Float(value))
            case .formantCompensate:
                self.bridge?.setFormantCompensate(value != 0)
            }
        }
        // NOTE: do NOT set `implementorValueProvider`. Reading `param.value` from inside
        // the provider re-enters the provider (that's what the getter calls), which
        // recurses until the stack overflows -> EXC_BAD_ACCESS. With no provider set,
        // AUParameter serves its own cached value, which is what we want here since the
        // DSP never owns a value the UI can't already see.
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

    public override var shouldBypassEffect: Bool {
        get { bypassBox.isBypassed }
        set { bypassBox.isBypassed = newValue }
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
        let bridge = SignalsmithBridge(sampleRate: sampleRate, channelCount: channelCount)
        bridge.setSemitones(Float(semitonesParam.value))
        bridge.setFormantSemitones(Float(formantSemitonesParam.value))
        bridge.setFormantCompensate(formantCompensateParam.value != 0)
        if let mode = TransposerLatencyMode(rawValue: Int(latencyModeParam.value)) {
            bridge.request(mode)
        }

        let maxFrames = Int(maximumFramesToRender)
        state.scratchInput = Array(repeating: [Float](repeating: 0, count: maxFrames), count: channelCount)
        state.scratchInputPointers = Array(repeating: nil, count: channelCount)
        state.outputPointers = Array(repeating: nil, count: channelCount)
        state.outputScratch = Array(repeating: [Float](repeating: 0, count: maxFrames), count: channelCount)
        // Published last: the render block treats a non-nil bridge as "buffers are ready".
        state.bridge = bridge
    }

    public override func deallocateRenderResources() {
        state.bridge = nil
        state.scratchInput = []
        state.scratchInputPointers = []
        state.outputPointers = []
        state.outputScratch = []
        super.deallocateRenderResources()
    }

    public override var internalRenderBlock: AUInternalRenderBlock {
        // Capture the two boxes strongly, once. Neither `self` nor any of its stored
        // buffers is captured, so there's no per-call weak-load lock and no reliance on
        // `self` outliving the block. The boxes are the only mutable state the render
        // thread reads, and `allocateRenderResources()` fills them before publishing
        // `state.bridge`.
        let state = self.state
        let bypassBox = self.bypassBox

        return { actionFlags, timestamp, frameCount, outputBusNumber, outputData, realtimeEventListHead, pullInputBlock in
            guard let bridge = state.bridge else { return kAudioUnitErr_Uninitialized }
            guard let pullInputBlock = pullInputBlock else { return kAudioUnitErr_NoConnection }

            // Walk host-delivered automation events (recorded automation lanes, some
            // hosts' knob gestures) and apply them directly to the DSP. Both parameters
            // are indexed/stepped, so no ramping is needed.
            var event = realtimeEventListHead
            while let e = event {
                if e.pointee.head.eventType == .parameter {
                    let paramEvent = e.pointee.parameter
                    if let address = TransposerParameterAddress(rawValue: paramEvent.parameterAddress) {
                        switch address {
                        case .semitones:
                            bridge.setSemitones(Float(paramEvent.value))
                        case .latencyMode:
                            if let mode = TransposerLatencyMode(rawValue: Int(paramEvent.value)) {
                                bridge.request(mode)
                            }
                        case .formantSemitones:
                            bridge.setFormantSemitones(Float(paramEvent.value))
                        case .formantCompensate:
                            bridge.setFormantCompensate(paramEvent.value != 0)
                        }
                    }
                }
                event = UnsafePointer(e.pointee.head.next)
            }

            let bufferList = UnsafeMutableAudioBufferListPointer(outputData)
            let channelCount = bufferList.count
            let frames = Int(frameCount)

            // A host may legally hand us buffers with mData == nil, meaning we're
            // expected to supply the memory ourselves. Point those at our persistent
            // output scratch buffer before pulling input into them.
            for i in 0..<channelCount {
                if bufferList[i].mData == nil, i < state.outputScratch.count {
                    state.outputScratch[i].withUnsafeMutableBufferPointer { buf in
                        bufferList[i].mData = UnsafeMutableRawPointer(buf.baseAddress!)
                    }
                    bufferList[i].mDataByteSize = UInt32(frames * MemoryLayout<Float>.size)
                }
            }

            var inputFlags = AudioUnitRenderActionFlags()
            let status = pullInputBlock(&inputFlags, timestamp, frameCount, 0, outputData)
            if status != noErr { return status }

            if bypassBox.isBypassed {
                // outputData already holds the pulled input samples (in-place pull) —
                // passthrough is a no-op. Skip the DSP entirely.
                return noErr
            }

            // Write into the persistent instance-level pointer arrays in place (index
            // assignment, not append) so no array backing store is allocated per render call.
            // Never walk past what `allocateRenderResources()` sized: a host can hand us
            // more channels than the bus format promised.
            let safeChannels = min(channelCount, state.scratchInput.count)
            for i in 0..<safeChannels {
                guard let mData = bufferList[i].mData else { continue }
                let outPtr = mData.assumingMemoryBound(to: Float.self)
                state.scratchInput[i].withUnsafeMutableBufferPointer { scratch in
                    scratch.baseAddress!.update(from: outPtr, count: frames)
                    state.scratchInputPointers[i] = UnsafePointer(scratch.baseAddress!)
                }
                state.outputPointers[i] = outPtr
            }

            // The bridge was configured for `state.scratchInput.count` channels and
            // always dereferences that many pointers. If the host handed us fewer
            // buffers than the bus format promised, the tail slots would still hold
            // nil (or a stale pointer from a previous call) — point them at our own
            // scratch so the DSP reads silence instead of crashing.
            if safeChannels < state.scratchInput.count {
                for i in safeChannels..<state.scratchInput.count {
                    state.scratchInput[i].withUnsafeMutableBufferPointer { scratch in
                        scratch.baseAddress!.update(repeating: 0, count: frames)
                        state.scratchInputPointers[i] = UnsafePointer(scratch.baseAddress!)
                    }
                    state.outputScratch[i].withUnsafeMutableBufferPointer { scratch in
                        state.outputPointers[i] = scratch.baseAddress!
                    }
                }
            }

            state.scratchInputPointers.withUnsafeMutableBufferPointer { inBuf in
                state.outputPointers.withUnsafeMutableBufferPointer { outBuf in
                    bridge.processInputs(inBuf.baseAddress!, outputs: outBuf.baseAddress!, frameCount: frameCount)
                }
            }
            return noErr
        }
    }
}
