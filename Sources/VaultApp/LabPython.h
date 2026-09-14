#import <Foundation/Foundation.h>
typedef char * _Nullable (*VaultGPUCallback)(const char * _Nonnull);
@interface LabPython : NSObject
+ (void)setModelCallback:(VaultGPUCallback _Nonnull)callback;
+ (void)setGPUCallback:(VaultGPUCallback _Nonnull)callback;
+ (NSString * _Nullable)initializeAt:(NSString * _Nonnull)bundle error:(NSString * _Nullable * _Nullable)error;
+ (NSString * _Nonnull)dispatch:(NSString * _Nonnull)request;
+ (void)cancel;
@end
