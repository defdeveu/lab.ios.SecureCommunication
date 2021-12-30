#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RSAUtils : NSObject

// return base64 encoded string
+ (NSString * _Nullable)encryptString:(NSString *)str publicKey:(NSString *)pubKey;
// return raw data
+ (NSData * _Nullable)encryptData:(NSData *)data publicKey:(NSString *)pubKey;
// return base64 encoded string
+ (NSString * _Nullable)encryptString:(NSString *)str privateKey:(NSString *)privKey;
// return raw data
+ (NSData * _Nullable)encryptData:(NSData *)data privateKey:(NSString *)privKey;

// decrypt base64 encoded string, convert result to string(not base64 encoded)
+ (NSString * _Nullable)decryptString:(NSString *)str publicKey:(NSString *)pubKey;
+ (NSData * _Nullable)decryptData:(NSData *)data publicKey:(NSString *)pubKey;
+ (NSString * _Nullable)decryptString:(NSString *)str privateKey:(NSString *)privKey;
+ (NSData * _Nullable)decryptData:(NSData *)data privateKey:(NSString *)privKey;

@end

NS_ASSUME_NONNULL_END
