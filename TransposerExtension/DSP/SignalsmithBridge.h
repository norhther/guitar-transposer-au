#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, TransposerLatencyMode) {
    TransposerLatencyModeFast = 0,
    TransposerLatencyModeBalanced = 1,
    TransposerLatencyModeQuality = 2
};

NS_ASSUME_NONNULL_BEGIN

@interface SignalsmithBridge : NSObject

- (instancetype)initWithSampleRate:(double)sampleRate
                       channelCount:(NSInteger)channelCount NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Thread-safe from any thread. Takes effect on the render thread at the start of its
/// next -processInputs:outputs:frameCount: call.
- (void)requestLatencyMode:(TransposerLatencyMode)mode;

/// Thread-safe from any thread. Total input+output latency, in samples, for the mode
/// currently applied on the render thread.
- (NSInteger)appliedLatencySamples;

/// Thread-safe from any thread.
- (void)setSemitones:(float)semitones;

/// Thread-safe from any thread.
- (void)setFormantSemitones:(float)semitones;

/// Thread-safe from any thread.
- (void)setFormantCompensate:(BOOL)compensatePitch;

/// Thread-safe from any thread. When enabled, block/overlap come from
/// -setAdvancedBlockMilliseconds:/-setAdvancedOverlap: instead of the latency-mode
/// preset. Takes effect on the render thread's next call, like -requestLatencyMode:.
- (void)setAdvancedEnabled:(BOOL)enabled;

/// Thread-safe from any thread. STFT block length in milliseconds (advanced mode only).
- (void)setAdvancedBlockMilliseconds:(float)milliseconds;

/// Thread-safe from any thread. Block/interval ratio, e.g. 4 = 4x overlap (advanced mode only).
- (void)setAdvancedOverlap:(float)overlap;

/// Thread-safe from any thread. 0...1: how much of the spectrum gets phase-locked
/// "tonal" treatment vs randomized "noise-like" treatment. Applied every render call,
/// no reconfigure needed.
- (void)setTonalityLimit:(float)tonalityLimit;

/// Thread-safe from any thread. Peak absolute sample value (0...1 for normal signal
/// levels) observed on the most recent -processInputs:outputs:frameCount: call.
- (float)inputPeak;
- (float)outputPeak;

/// Render-thread only. Applies any pending latency-mode change, then processes
/// frameCount frames from inputs into outputs (both [channel][frame] laid out,
/// channelCount channels as given at init). inputs and outputs must not alias.
- (void)processInputs:(const float * const *)inputs
               outputs:(float * const *)outputs
            frameCount:(uint32_t)frameCount;

@end

NS_ASSUME_NONNULL_END
