//
//  I18Runtime.m
//  iOS18Customization
//
//  Small runtime helpers. All hooks go through I18HookMethod() so a missing
//  class or selector on some 15.x build only disables that one hook instead
//  of crashing SpringBoard.
//

#import "I18Shared.h"
#include <substrate.h>

static BOOL I18ClassOwnsMethod(Class cls, SEL sel) {
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    BOOL found = NO;
    for (unsigned int i = 0; i < count; i++) {
        if (method_getName(methods[i]) == sel) {
            found = YES;
            break;
        }
    }
    free(methods);
    return found;
}

BOOL I18HookMethod(Class cls, SEL sel, IMP replacement, IMP *original) {
    if (!cls || !sel || !replacement) return NO;
    Method method = class_getInstanceMethod(cls, sel);
    if (!method) {
        I18Log(@"skip hook -[%@ %@]: not found", NSStringFromClass(cls), NSStringFromSelector(sel));
        return NO;
    }
    if (I18ClassOwnsMethod(cls, sel)) {
        MSHookMessageEx(cls, sel, replacement, original);
        return *original != NULL;
    }
    // Inherited (e.g. UIView's -didMoveToWindow): add an override to this
    // class only and call the inherited implementation from it.
    IMP inherited = method_getImplementation(method);
    if (!class_addMethod(cls, sel, replacement, method_getTypeEncoding(method))) return NO;
    *original = inherited;
    return YES;
}

id I18ValueForKey(id object, NSString *key) {
    if (!object || key.length == 0) return nil;
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

id I18Call(id target, NSString *selectorName) {
    if (!target) return nil;
    SEL sel = NSSelectorFromString(selectorName);
    if (![target respondsToSelector:sel]) return nil;
    NSMethodSignature *signature = [target methodSignatureForSelector:sel];
    if (signature.numberOfArguments != 2) return nil;
    const char *returnType = signature.methodReturnType;
    if (returnType[0] == '@') {
        return ((id (*)(id, SEL))objc_msgSend)(target, sel);
    }
    if (returnType[0] == 'v') {
        ((void (*)(id, SEL))objc_msgSend)(target, sel);
    }
    return nil;
}

BOOL I18ClassNameContains(id object, NSString *needle) {
    if (!object) return NO;
    const char *name = object_getClassName(object);
    if (!name) return NO;
    return strstr(name, needle.UTF8String) != NULL;
}
