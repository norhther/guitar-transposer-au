#import "SignalsmithBridge.h"
#import <atomic>
#import <algorithm>
#import <cmath>
#include <fenv.h>
#include "signalsmith-stretch.h"

/// ARM doesn't auto-flush denormals like x86 SSE. A decaying sustained note pushes the
/// STFT's internal buffers into denormal range, and denormal float math runs 10-100x
/// slower on some cores -> can miss the render deadline -> dropout on long notes/chords.
/// FE_DFL_DISABLE_DENORMS_ENV flushes denormals to zero for this thread.
static void TransposerEnableFlushToZero(void) {
    fesetenv(FE_DFL_DISABLE_DENORMS_ENV);
}

/// Block length in seconds per mode.
///
/// These must stay in the same ballpark as the library's own presets, which are what
/// the reference demo uses: presetDefault is block = SR*0.12, interval = SR*0.03;
/// presetCheaper is 0.1 / 0.04. The block length sets the STFT's frequency resolution
/// (bin spacing = SR/blockSamples), so shrinking it to chase latency destroys pitch
/// tracking: a 16 ms block gives ~62 Hz bins, which cannot separate a low-E guitar
/// fundamental (82 Hz) from its neighbours -> phase smearing and audible artifacts.
/// 60 ms (~16 Hz bins) is about the floor for guitar-range material.
static int TransposerBlockSamples(double sampleRate, TransposerLatencyMode mode) {
    double blockSeconds;
    switch (mode) {
        case TransposerLatencyModeFast:     blockSeconds = 0.06; break;
        case TransposerLatencyModeBalanced: blockSeconds = 0.09; break;
        case TransposerLatencyModeQuality:  blockSeconds = 0.12; break;
        default:                            blockSeconds = 0.09; break;
    }
    return std::max(256, static_cast<int>(sampleRate * blockSeconds));
}

@implementation SignalsmithBridge {
    signalsmith::stretch::SignalsmithStretch<float> _stretch;
    double _sampleRate;
    int _channelCount;
    std::atomic<int> _pendingLatencyMode;
    std::atomic<int> _appliedLatencyMode;
    std::atomic<long> _appliedLatencySamples;
    std::atomic<float> _semitones;
    std::atomic<float> _formantSemitones;
    std::atomic<bool> _formantCompensate;
    std::atomic<float> _inputPeak;
    std::atomic<float> _outputPeak;
}

- (instancetype)initWithSampleRate:(double)sampleRate channelCount:(NSInteger)channelCount {
    self = [super init];
    if (self) {
        _sampleRate = sampleRate;
        _channelCount = static_cast<int>(channelCount);
        _semitones.store(0.0f, std::memory_order_relaxed);
        _formantSemitones.store(0.0f, std::memory_order_relaxed);
        _formantCompensate.store(false, std::memory_order_relaxed);
        _pendingLatencyMode.store(TransposerLatencyModeBalanced, std::memory_order_relaxed);
        _appliedLatencyMode.store(-1, std::memory_order_relaxed);
        _appliedLatencySamples.store(0, std::memory_order_relaxed);
        _inputPeak.store(0.0f, std::memory_order_relaxed);
        _outputPeak.store(0.0f, std::memory_order_relaxed);
        [self applyLatencyMode:TransposerLatencyModeBalanced];
    }
    return self;
}

- (void)applyLatencyMode:(TransposerLatencyMode)mode {
    int blockSamples = TransposerBlockSamples(_sampleRate, mode);
    // 4x overlap, matching presetDefault's 0.12 / 0.03 ratio.
    int intervalSamples = std::max(64, blockSamples / 4);
    // splitComputation=true: block is 60-120ms, way bigger than a render callback
    // (~5-10ms). Without splitting, hitting a block boundary makes process() do the
    // whole STFT synchronously on the render thread in one call -> can starve the
    // callback deadline -> dropout, not spectral smearing, but same symptom. Splitting
    // spreads that work across calls (presetCheaper does the same for this reason).
    _stretch.configure(_channelCount, blockSamples, intervalSamples, true);
    _appliedLatencyMode.store(mode, std::memory_order_relaxed);
    long total = static_cast<long>(_stretch.inputLatency()) + static_cast<long>(_stretch.outputLatency());
    _appliedLatencySamples.store(total, std::memory_order_relaxed);
}

- (void)requestLatencyMode:(TransposerLatencyMode)mode {
    _pendingLatencyMode.store(mode, std::memory_order_relaxed);
}

- (NSInteger)appliedLatencySamples {
    return static_cast<NSInteger>(_appliedLatencySamples.load(std::memory_order_relaxed));
}

- (void)setSemitones:(float)semitones {
    _semitones.store(semitones, std::memory_order_relaxed);
}

- (void)setFormantSemitones:(float)semitones {
    _formantSemitones.store(semitones, std::memory_order_relaxed);
}

- (void)setFormantCompensate:(BOOL)compensatePitch {
    _formantCompensate.store(compensatePitch, std::memory_order_relaxed);
}

- (float)inputPeak {
    return _inputPeak.load(std::memory_order_relaxed);
}

- (float)outputPeak {
    return _outputPeak.load(std::memory_order_relaxed);
}

static float TransposerPeakAbs(const float *samples, uint32_t frameCount) {
    float peak = 0.0f;
    for (uint32_t i = 0; i < frameCount; i++) {
        peak = std::max(peak, std::fabs(samples[i]));
    }
    return peak;
}

static float TransposerPeakAbsAllChannels(const float * const *channels, int channelCount, uint32_t frameCount) {
    float peak = 0.0f;
    for (int c = 0; c < channelCount; c++) {
        peak = std::max(peak, TransposerPeakAbs(channels[c], frameCount));
    }
    return peak;
}

- (void)processInputs:(const float * const *)inputs
               outputs:(float * const *)outputs
            frameCount:(uint32_t)frameCount {
    TransposerEnableFlushToZero();
    int pending = _pendingLatencyMode.load(std::memory_order_relaxed);
    if (pending != _appliedLatencyMode.load(std::memory_order_relaxed)) {
        [self applyLatencyMode:static_cast<TransposerLatencyMode>(pending)];
    }
    _inputPeak.store(TransposerPeakAbsAllChannels(inputs, _channelCount, frameCount), std::memory_order_relaxed);
    _stretch.setTransposeSemitones(_semitones.load(std::memory_order_relaxed));
    _stretch.setFormantSemitones(_formantSemitones.load(std::memory_order_relaxed),
                                  _formantCompensate.load(std::memory_order_relaxed));
    _stretch.process(inputs, static_cast<int>(frameCount), outputs, static_cast<int>(frameCount));
    _outputPeak.store(TransposerPeakAbsAllChannels(outputs, _channelCount, frameCount), std::memory_order_relaxed);
}

@end
