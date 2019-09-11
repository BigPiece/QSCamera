//
//  QSCamera.h
//  QSCamera
//
//  Created by qws on 2018/9/12.
//  Copyright © 2018年 qws. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import "GPUImage.h"
#import "CVPixelBufferTools.h"
#import <GLKit/GLKView.h>
#import "QSGLKView.h"
#import "QSMediaManager.h"

@protocol QSCameraDelegate <NSObject>
- (void)willOutput:(AVCaptureOutput *)output sampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection;
- (void)willOutput:(AVCaptureOutput *)output metadataObjects:(NSArray<__kindof AVMetadataObject *> *)metadataObjects fromConnection:(AVCaptureConnection *)connection;

@end

@interface QSCamera : GPUImageOutput
{
    GPUImageRotationMode outputRotation, internalRotation;
}
@property (nonatomic, weak) id<QSCameraDelegate> delegate;
@property (nonatomic, strong) AVCaptureDevice *inputDevice;
@property (nonatomic, weak) QSGLKView *glkView;
@property (nonatomic, readwrite) BOOL horizontallyMirrorFrontFacingCamera, horizontallyMirrorRearFacingCamera;
@property (nonatomic, readwrite) UIInterfaceOrientation outputImageOrientation;

//启动
- (void)startRunning;
//暂停
- (void)stopRunning;
//旋转相机
- (void)rotateCamera;
//拍摄照片
- (void)capturePhoto;

//手电筒
+ (void)setTorchOn:(BOOL)torchOn forDevice:(AVCaptureDevice *)device;
+ (void)setTorchLevel:(CGFloat)value forDevice:(AVCaptureDevice *)device;

//闪光灯
+ (void)setFlashOn:(BOOL)flashOn forDevice:(AVCaptureDevice *)device;

//Zoom
+ (void)setZoomFactor:(CGFloat)factor normalized:(BOOL)normalized forDevice:(AVCaptureDevice *)device;

//焦距
typedef NS_ENUM( NSInteger, FocusType ) {
    FocusTypeAuto,
    FocusTypeClose,
    FocusTypeMedium,
    FocusTypeFar,
};
+ (CGFloat)focusLenByType:(FocusType)focusType;
+ (void)setAutoFocus:(BOOL)focus focusType:(FocusType)focusType forDevice:(AVCaptureDevice *)device;
+ (void)setFocusLens:(CGFloat)value forDevice:(AVCaptureDevice *)device;

//曝光补偿
typedef NS_ENUM(NSInteger, ExposureBiasType) {
    ExposureBiasTypePlus2,       // +1.2
    ExposureBiasTypePlus1,       // +0.6
    ExposureBiasTypeNone,        //  0
    ExposureBiasTypeMinus1,      // -2.0
    ExposureBiasTypeMinus2       // -4.0
};
+ (void)setExposureBiasValue:(float)value normalized:(BOOL)normalized forDevice:(AVCaptureDevice *)device;

//白平衡
typedef NS_ENUM(NSInteger, WhiteBalanceType) {
    WhiteBalanceTypeAuto,       // 自动
    WhiteBalanceTypeLamp,       // 白炽灯
    WhiteBalanceTypeFluorescent,// 日光灯
    WhiteBalanceTypeSunlight,   // 阳光
    WhiteBalanceTypeCloud,      // 阴天
    WhiteBalanceTypeShadow      // 阴影
};
+ (void)setWhiteBalanceType:(WhiteBalanceType)type forDevice:(AVCaptureDevice *)device;
+ (void)setWhiteBalance:(CGFloat)value normalized:(BOOL)normalized forDevice:(AVCaptureDevice *)device ;

//ISO 和 曝光时长
typedef NS_ENUM(NSInteger, ISODurationType) {
    ISODurationTypeValue,  // 当前值
    ISODurationTypeCustom, // 用户设置的
    ISODurationTypeDefault,// 默认的
};
+ (void)setISO:(CGFloat)iValue iType:(ISODurationType)iType iNor:(BOOL)iNor duration:(CGFloat)duration dType:(ISODurationType)dType dNor:(BOOL)dNor forDevice:(AVCaptureDevice *)device;

//兴趣点 焦点和曝光
+ (void)setInterestPoint:(CGPoint)point focus:(BOOL)fEnable fAuto:(BOOL)fAuto exposure:(BOOL)eEnable eAuto:(BOOL)eAuto forDevice:(AVCaptureDevice *)device;

//Auto
+ (void)setAutoFocus:(BOOL)focus exposure:(BOOL)exposure whiteBalance:(BOOL)whiteBalance forDevice:(AVCaptureDevice *)device; // 允许自动对焦、曝光、白平衡

//Size
//+ (CGSize)setBestFullSizeFormatForDevice:(AVCaptureDevice *)device; // 最大相机配置 (画面比例4:3且>1920*1080) - 1200:900
+ (CGSize)setBestVideoSizeFormatForDevice:(AVCaptureDevice *)device; // 相机配置 (画面比例16:9且>=1920*1080) - 1920:1080

+ (CGSize)getDeviceSizeFromDevice:(AVCaptureDevice *)device;
+ (CGSize)getPreviewSizeFromSize:(CGSize)size;
+ (CGSize)getDraftSizeFromSize:(CGSize)size;
+ (CGSize)scaleSize:(CGSize)size withMaxPixel:(CGFloat)maxPixel;
+ (BOOL)isMoreThan2GBMemory;

//FPS
+ (void)setBestFPSForDevice:(AVCaptureDevice *)device;

//Orientation
+ (UIImageOrientation)realImageOriWithDevideOri:(UIDeviceOrientation)ori devicePosition:(AVCaptureDevicePosition)devicePosition;


@end
