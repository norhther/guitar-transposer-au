#import "SignalsmithBridge.h"
#import <atomic>
#import <algorithm>
#import <cmath>
#include "signalsmith-stretch.h"

static int TransposerBlockSamples(double sampleRate, TransposerLatencyMode mode) {
    double blockSeconds;
    switch (mode) {
        case TransposerLatencyModeFast:     blockSeconds = 0.008; break;
        case TransposerLatencyModeBalanced: blockSeconds = 0.016; break;
        case TransposerLatencyModeQuality:  blockSeconds = 0.032; break;
        default:                            blockSeconds = 0.016; break;
    }
    return std::max(64, static_cast<int>(sampleRate * blockSeconds));
}

@implementation SignalsmithBridge {
    signalsmith::stretch::SignalsmithStretch<float> _stretch;
    double _sampleRate;
    int _channelCount;
    std::atomic<int> _pendingLatencyMode;
    std::atomic<int> _appliedLatencyMode;
    std::atomic<long> _appliedLatencySamples;
    std::atomic<float> _semitones;
    std::atomic<float> _inputPeak;
    std::atomic<float> _outputPeak;
}

- (instancetype)initWithSampleRate:(double)sampleRate channelCount:(NSInteger)channelCount {
    self = [super init];
    if (self) {
        _sampleRate = sampleRate;
        _channelCount = static_cast<int>(channelCount);
        _semitones.store(0.0f, std::memory_order_relaxed);
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
    int intervalSamples = std::max(32, blockSamples / 3);
    _stretch.configure(_channelCount, blockSamples, intervalSamples);
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
    int pending = _pendingLatencyMode.load(std::memory_order_relaxed);
    if (pending != _appliedLatencyMode.load(std::memory_order_relaxed)) {
        [self applyLatencyMode:static_cast<TransposerLatencyMode>(pending)];
    }
    _inputPeak.store(TransposerPeakAbsAllChannels(inputs, _channelCount, frameCount), std::memory_order_relaxed);
    _stretch.setTransposeSemitones(_semitones.load(std::memory_order_relaxed));
    _stretch.process(inputs, static_cast<int>(frameCount), outputs, static_cast<int>(frameCount));
    _outputPeak.store(TransposerPeakAbsAllChannels(outputs, _channelCount, frameCount), std::memory_order_relaxed);
}

@end
