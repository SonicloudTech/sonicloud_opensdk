#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Objective-C surface for the C++ sherpa-onnx C API adapter.
///
/// The class is intentionally small so Flutter and Swift only depend on this
/// stable boundary. Model files remain outside the application bundle and are
/// installed under the caller-provided model root.
@interface SoniCloudSherpaVoiceRuntime : NSObject

- (instancetype)initWithModelRoot:(NSString *)modelRoot NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (NSDictionary<NSString *, id> *)capabilities;
- (BOOL)prepareModelsWithLanguage:(nullable NSString *)language
                            error:(NSError * _Nullable * _Nullable)error;
- (nullable NSDictionary<NSString *, id> *)transcribeWithPath:(NSString *)path
                                                      language:(NSString *)language
                                                         error:(NSError * _Nullable * _Nullable)error;
- (nullable NSDictionary<NSString *, id> *)synthesizeWithText:(NSString *)text
                                                       language:(NSString *)language
                                                          voice:(NSString *)voice
                                                          speed:(double)speed
                                                          error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
