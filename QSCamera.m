//
//  QSCamera.m
//  QSCamera
//
//  Created by qws on 2018/9/12.
//  Copyright © 2018年 qws. All rights reserved.
//

#import "QSCamera.h"
#import "CVPixelBufferTools.h"
#import "DepthTool.h"
#import "ImageMetaDataUtils.h"
#import "QSMediaManager.h"
#import "ValueDefinitions.h"
#import "QSFacePPTool.h"

API_AVAILABLE(ios(11.1))
@interface QSCamera()<AVCapturePhotoCaptureDelegate,AVCaptureVideoDataOutputSampleBufferDelegate,AVCaptureAudioDataOutputSampleBufferDelegate, AVCaptureDepthDataOutputDelegate,AVCaptureMetadataOutputObjectsDelegate>

@property (nonatomic, strong) AVCaptureSession *session;
@property (nonatomic, strong) AVCaptureDeviceInput *deviceInput;

@property (nonatomic, strong) AVCaptureSessionPreset preset;
@property (nonatomic, assign) AVCaptureDevicePosition devicePosition;

@property (nonatomic, strong) AVCaptureStillImageOutput *stillImageOutput;
@property (nonatomic, strong) AVCaptureAudioDataOutput *audioOutput;
@property (nonatomic, strong) AVCaptureVideoDataOutput *videoOutput;
@property (nonatomic, assign) AVCaptureVideoOrientation videoOrientation;
@property (nonatomic, strong) dispatch_queue_t outputProcessQueue;
@property (nonatomic, strong) dispatch_queue_t metadataProcessQueue;

@property (nonatomic, strong) AVCaptureMetadataOutput *metadataOutput;
//IOS10
@property (nonatomic, strong) AVCapturePhotoOutput *photoOutput;
//IOS11
@property (nonatomic, strong) AVDepthData *outputDepthData;
@property (nonatomic, strong) AVCaptureDepthDataOutput *depthOutput;
@property (nonatomic, strong) AVCaptureDataOutputSynchronizer *depthSynchronizer;

// session状态
@property (nonatomic, assign) AVCaptureDevicePosition lastPosition;
@property (nonatomic, assign) BOOL lastUseDepth;
@property (nonatomic, assign) BOOL currentUseDepth;

@end

@implementation QSCamera
@synthesize horizontallyMirrorFrontFacingCamera = _horizontallyMirrorFrontFacingCamera, horizontallyMirrorRearFacingCamera = _horizontallyMirrorRearFacingCamera;
@synthesize devicePosition = _devicePosition;
@synthesize outputImageOrientation = _outputImageOrientation;


- (instancetype)init
{
    self = [super init];
    if (self) {
        outputRotation = kGPUImageNoRotation;
        internalRotation = kGPUImageNoRotation;
        self.horizontallyMirrorFrontFacingCamera = YES;
        self.currentUseDepth = self.lastUseDepth = NO;
        [self configureWith:(QSMediaTypeImage)];
    }
    return self;
}

- (BOOL)checkNeedResetInput {
    BOOL depthChanged    = self.currentUseDepth != self.lastUseDepth;
    BOOL positionChanged = self.lastPosition != self.devicePosition;
    BOOL noInputDevice   = !_inputDevice;
//    NSLog(@"depthChanged = %d , positionChanged = %d, noInputDevice = %d",depthChanged,positionChanged,noInputDevice);
    return depthChanged || positionChanged || noInputDevice;
}

- (BOOL)checkNeedResetOutput {
    BOOL depthChanged = self.currentUseDepth != self.lastUseDepth;
    BOOL noVideoOutput = !_videoOutput;
    BOOL positionChanged = self.lastPosition != self.devicePosition;
//    NSLog(@"depthChanged = %d , noVideoOutput = %d",depthChanged,noVideoOutput);
    return depthChanged || noVideoOutput || positionChanged;
}

- (void)configureWith:(QSMediaType)type {
    
    BOOL needResetInput  = [self checkNeedResetInput];
    BOOL needResetOutput = [self checkNeedResetOutput];
    self.lastUseDepth = self.currentUseDepth;
    self.lastPosition = self.devicePosition;
    
    //设置InputDevice
    if (needResetInput) {
        self.inputDevice = [self.class findDeviceWithPosition:self.devicePosition useDepth:NO];
        NSError *error = nil;
        self.deviceInput = [AVCaptureDeviceInput deviceInputWithDevice:self.inputDevice error:&error];
        if (error) {
            NSLog(@"error at create AVCaptureDeviceInput");
        }
    }
    
    //如果开启Depth则需要提前配置
    if (self.currentUseDepth && _photoOutput) {
        [self photoOutput];
        [self depthOutput];
    }
    
    if (!self.currentUseDepth && !_stillImageOutput) {
        [self stillImageOutput];
    }
    
    if (!_videoOutput) {
        [self videoOutput];
    }
    
    [self.session beginConfiguration];
    
    //input
    if (needResetInput) {
        for (int i = 0; i<self.session.inputs.count; i++) {
            [self.session removeInput:self.session.inputs[i]];
        }
        if ([self.session canAddInput:self.deviceInput]){
            [self.session addInput:self.deviceInput];
        }
    }
    
    //output
    if (needResetOutput) {
        for (int i = 0; i<self.session.outputs.count; i++) {
            [self.session removeOutput:self.session.outputs[i]];
        }
        if ([self.session canAddOutput:self.videoOutput]) {
            [self.session addOutput:self.videoOutput];
        }
        
        if ([self.session canAddOutput:self.metadataOutput]) {//face
            [self.session addOutput:self.metadataOutput];
        }
        if (self.currentUseDepth) {
            if ([self.session canAddOutput:self.photoOutput]) {
                [self.session addOutput:self.photoOutput];
                if (@available(iOS 11.0, *)) {
                    if (self.photoOutput.isDepthDataDeliverySupported) {
                        self.photoOutput.depthDataDeliveryEnabled = YES;
                    }
                } else {
                    // Fallback on earlier versions
                }
            }
            if ([self.session canAddOutput:self.depthOutput]) {
                [self.session addOutput:self.depthOutput];
            }
        } else {
            if ([self.session canAddOutput:self.stillImageOutput]) {
                [self.session addOutput:self.stillImageOutput];
            }
        }
       
    }
    
//    if ([self.session canAddOutput:self.audioOutput]) {
//        [self.session addOutput:self.audioOutput];
//    }
    
    AVCaptureSessionPreset preset = AVCaptureSessionPresetPhoto;
    if ([self.session canSetSessionPreset:preset]) {
        [self.session setSessionPreset:preset];
    } else {
        NSLog(@"camera session can not set preset");
    }
    [self.session commitConfiguration];
    
    // 设置默认方向
    self.outputImageOrientation = UIInterfaceOrientationPortrait;
    // 设置metadata = face
    self.metadataOutput.metadataObjectTypes = @[AVMetadataObjectTypeFace];
}

#pragma mark -
#pragma mark - Action
- (void)startRunning {
    self.glkView.frontDevice = self.inputDevice.position == AVCaptureDevicePositionFront;
    if (!self.session.running) {
        [self.session startRunning];
    }
}

- (void)stopRunning {
    [self.session stopRunning];
}

- (void)rotateCamera{
    AVCaptureDevicePosition currentCameraPosition = [[self.deviceInput device] position];
    if (currentCameraPosition == AVCaptureDevicePositionBack){
        currentCameraPosition = AVCaptureDevicePositionFront;
    }else{
        currentCameraPosition = AVCaptureDevicePositionBack;
    }
    self.devicePosition = currentCameraPosition;
    [self configureWith:QSMediaTypeImage];
    
    _outputImageOrientation = UIInterfaceOrientationPortrait;
    [self setOutputImageOrientation:_outputImageOrientation];
    
//    _imageOrientation = [CameraHelper realImageOriWithDevideOri:self.deviceOrientation devicePosition:self.inputCamera.position];
}

- (void)refreshConfig{
   
}

#pragma mark -
#pragma mark - CapturePhoto
- (void)capturePhoto {
    if (self.currentUseDepth) {
        if (@available(iOS 11.0, *)) {
            [self captureDepthPhoto];
        }
    } else {
        [self captureStillPhoto];
    }
}

- (void)captureStillPhoto{
    [self.stillImageOutput captureStillImageAsynchronouslyFromConnection:[[_stillImageOutput connections] objectAtIndex:0] completionHandler:^(CMSampleBufferRef  _Nullable imageDataSampleBuffer, NSError * _Nullable error) {
        if (imageDataSampleBuffer) {
            [self saveImageToAlbumWith:imageDataSampleBuffer];
        }
    }];
}

- (void)saveImageToAlbumWith:(CMSampleBufferRef)sampleBuffer {
    UIImage *image = [CVPixelBufferTools getUIImageFromSampleBuffer:sampleBuffer];
    [QSMediaManager saveImage:image toAlbum:[QSMediaManager getDefaultAlbumName] success:^(id ret) {
        NSLog(@"success save image to album ");
    } failure:^(NSError *error) {
        NSLog(@"failre save image to album :%@",error);
    }];
}

//拍摄带depth的图片
- (void)captureDepthPhoto API_AVAILABLE(ios(11.0)){
    NSDictionary *format = [NSDictionary dictionaryWithObject:[NSNumber numberWithInt: kCVPixelFormatType_32BGRA] forKey:(id)kCVPixelBufferPixelFormatTypeKey];
    AVCapturePhotoSettings *photoSetting = [AVCapturePhotoSettings photoSettingsWithFormat:format];
    photoSetting.depthDataDeliveryEnabled = YES; //启用depth
    photoSetting.embedsDepthDataInPhoto = YES; //depth信息写入图片
    photoSetting.depthDataFiltered = YES; //启用depth填充不支持的值
    if (self.photoOutput.cameraCalibrationDataDeliverySupported) {
        photoSetting.cameraCalibrationDataDeliveryEnabled = YES;
    }
    [self.photoOutput capturePhotoWithSettings:photoSetting delegate:self];
}

- (void)captureOutput:(AVCapturePhotoOutput *)output didFinishProcessingPhoto:(AVCapturePhoto *)photo error:(NSError *)error  API_AVAILABLE(ios(11.0))
{
    AVDepthData *depthData = photo.depthData;
    if (!depthData) {
        return;
    }
    
    //添加CIBlurEffect滤镜
    CVPixelBufferRef blurPixelBuffer = [DepthTool useDepthBlurWith:photo.pixelBuffer depthData:depthData];
    
    //旋转后在记录calibrationData
    depthData = [depthData depthDataByApplyingExifOrientation:(kCGImagePropertyOrientationRight)];
    self.outputDepthData = depthData;
    
    UIImage *image = [DepthTool getUIImageFromCVPixelBuffer:blurPixelBuffer uiOrientation:UIImageOrientationRight];
    
    ImageMetaDataUtils *metadata = [ImageMetaDataUtils metaDataFromDict:photo.metadata];
    
    //    NOMOImageProcessModel *model = [NOMOImageProcessModel new];
    //    model.image = image;
    //    model.currentSkin = NOMOSkin_Depth;
    //    model.isFront = self.inputCamera.position == AVCaptureDevicePositionFront;
    //    model.doubleMode = self.doubleExposureMode;
    //    model.metadata = metadata;
    //    model.depthData = depthData;
    //    [self.imageProcessor processImage:model];
}

#pragma mark -
#pragma mark - Delegate

// iOS11使用OutputSynchronizer则不在走该方法
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection{
    runSynchronouslyOnVideoProcessingQueue(^{
        if ([self.delegate respondsToSelector:@selector(willOutput:sampleBuffer:fromConnection:)]) {
            [self.delegate willOutput:output sampleBuffer:sampleBuffer fromConnection:connection];
        }
        [self processSampleBuffer:sampleBuffer];
    });
}
// iOS11使用OutputSynchronizer则不在走该方法
- (void)depthDataOutput:(AVCaptureDepthDataOutput *)output didOutputDepthData:(AVDepthData *)depthData timestamp:(CMTime)timestamp connection:(AVCaptureConnection *)connection  API_AVAILABLE(ios(11.0)) {
}

// 处理samplebuffer
- (void)processSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    [self userGPUImageOutputWithSmapleBuffer:sampleBuffer];
}

- (void)userGPUImageOutputWithSmapleBuffer:(CMSampleBufferRef)sampleBuffer {
    CMTime currentTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    int width = (int)CVPixelBufferGetWidth(pixelBuffer);
    int height = (int)CVPixelBufferGetHeight(pixelBuffer);
    int bytesPerRow = (int)CVPixelBufferGetBytesPerRow(pixelBuffer);
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    [GPUImageContext useImageProcessingContext];
    outputFramebuffer = [[GPUImageContext sharedFramebufferCache] fetchFramebufferForSize:(CGSizeMake(bytesPerRow / 4, height)) onlyTexture:YES];
    [outputFramebuffer activateFramebuffer];
    
    glBindTexture(GL_TEXTURE_2D, [outputFramebuffer texture]);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, bytesPerRow / 4, height, 0, GL_BGRA, GL_UNSIGNED_BYTE, CVPixelBufferGetBaseAddress(pixelBuffer));
    
    [self updateTargetsForVideoCameraUsingCacheTextureAtWidth:bytesPerRow/4 height:height time:currentTime];
    
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
}

- (void)updateTargetsForVideoCameraUsingCacheTextureAtWidth:(int)bufferWidth height:(int)bufferHeight time:(CMTime)currentTime;
{
    // First, update all the framebuffers in the targets
    for (id<GPUImageInput> currentTarget in targets)
    {
        if ([currentTarget enabled])
        {
            NSInteger indexOfObject = [targets indexOfObject:currentTarget];
            NSInteger textureIndexOfTarget = [[targetTextureIndices objectAtIndex:indexOfObject] integerValue];
            
            if (currentTarget != self.targetToIgnoreForUpdates)
            {
                [currentTarget setInputRotation:outputRotation atIndex:textureIndexOfTarget];
                [currentTarget setInputSize:CGSizeMake(bufferWidth, bufferHeight) atIndex:textureIndexOfTarget];
                
                if ([currentTarget wantsMonochromeInput])
                {
                    [currentTarget setCurrentlyReceivingMonochromeInput:YES];
                    // TODO: Replace optimization for monochrome output
                    [currentTarget setInputFramebuffer:outputFramebuffer atIndex:textureIndexOfTarget];
                }
                else
                {
                    [currentTarget setCurrentlyReceivingMonochromeInput:NO];
                    [currentTarget setInputFramebuffer:outputFramebuffer atIndex:textureIndexOfTarget];
                }
            }
            else
            {
                [currentTarget setInputRotation:outputRotation atIndex:textureIndexOfTarget];
                [currentTarget setInputFramebuffer:outputFramebuffer atIndex:textureIndexOfTarget];
            }
        }
    }
    
    // Then release our hold on the local framebuffer to send it back to the cache as soon as it's no longer needed
    [outputFramebuffer unlock];
    outputFramebuffer = nil;
    
    // Finally, trigger rendering as needed
    for (id<GPUImageInput> currentTarget in targets)
    {
        if ([currentTarget enabled])
        {
            NSInteger indexOfObject = [targets indexOfObject:currentTarget];
            NSInteger textureIndexOfTarget = [[targetTextureIndices objectAtIndex:indexOfObject] integerValue];
            if (currentTarget != self.targetToIgnoreForUpdates)
            {
                [currentTarget newFrameReadyAtTime:currentTime atIndex:textureIndexOfTarget];
            }
        }
    }
}

- (void)captureOutput:(AVCaptureOutput *)output didOutputMetadataObjects:(NSArray<__kindof AVMetadataObject *> *)metadataObjects fromConnection:(AVCaptureConnection *)connection {
    
    if ([self.delegate respondsToSelector:@selector(willOutput:metadataObjects:fromConnection:)]) {
        [self.delegate willOutput:output metadataObjects:metadataObjects fromConnection:connection];
    }
}

#pragma mark -
#pragma mark - Tools
+ (AVCaptureDevice *)findDeviceWithPosition:(AVCaptureDevicePosition)position useDepth:(BOOL)useDepth {
    AVCaptureDevice *target = nil;
    if (useDepth) {
        if (@available(iOS 11.1, *)) {
            AVCaptureDeviceDiscoverySession *sessions = [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInWideAngleCamera,AVCaptureDeviceTypeBuiltInDualCamera,AVCaptureDeviceTypeBuiltInTrueDepthCamera] mediaType:AVMediaTypeVideo position:position];
            NSArray *devices = sessions.devices;
            for (AVCaptureDevice *device in devices.reverseObjectEnumerator){
                if ([device position] == position) {
                    if (device.deviceType == AVCaptureDeviceTypeBuiltInDualCamera ||
                        device.deviceType == AVCaptureDeviceTypeBuiltInTrueDepthCamera) {
                        target = device;
                        break;
                    }
                }
            }
        }
    } else if ([UIDevice currentDevice].systemVersion.floatValue >= 10.0) {
        if (@available(iOS 10.0, *)) {
            AVCaptureDeviceDiscoverySession *sessions = [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInWideAngleCamera] mediaType:AVMediaTypeVideo position:position];
            NSArray *devices = sessions.devices;
            for (AVCaptureDevice *device in devices.reverseObjectEnumerator){
                if ([device position] == position) {
                    target = device;
                }
            }
        }
    } else {
        NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
        for (AVCaptureDevice *device in devices){
            if ([device position] == position){
                target = device;
            }
        }
    }
    return target;
}


/**
 曝光补偿EV

 @param type -2 -1 0 +1 +2
 @param device
 */
+ (void)setExposureBiasType:(ExposureBiasType)type forDevice:(AVCaptureDevice *)device{
    NSError *error = nil;
    if ( [device lockForConfiguration:&error] ) {
        float bias;
        switch (type) {
            case ExposureBiasTypePlus2:
                bias = 1.2;
                break;
            case ExposureBiasTypePlus1:
                bias = 0.6;
                break;
            case ExposureBiasTypeNone:
                bias = 0;
                break;
            case ExposureBiasTypeMinus1:
                bias = -1;
                break;
            case ExposureBiasTypeMinus2:
                bias = -2;
                break;
            default:
                break;
        }
        [device setExposureTargetBias:bias completionHandler:nil];
        [device unlockForConfiguration];
    }else {
        NSLog( @"Could not lock device for configuration: %@", error );
    }
}


/**
 曝光值

 @param value 值
 @param device device
 */
+ (void)setExposureBiasValue:(float)value normalized:(BOOL)normalized forDevice:(AVCaptureDevice *)device {
    NSError *error = nil;
    if ([device lockForConfiguration:&error]) { //set之前需要先锁定设备放置多线程冲突（添加线程锁）
        if (normalized) {
            value = value * device.maxExposureTargetBias;
            NSLog(@"maxEV = %f,minEV = %f",device.maxExposureTargetBias,device.minExposureTargetBias);
        }
        [device setExposureTargetBias:value completionHandler:^(CMTime syncTime) {
            NSLog(@"set setExposureTargetBias complete at time = %f",CMTimeGetSeconds(syncTime));
        }];
        [device unlockForConfiguration];
    }else {
        NSLog( @"Could not lock device for configuration: %@", error );
    }
}

/**
 白平衡类型

 @param type 自动/白炽灯/日光灯/阳光/阴天/阴影
 @param device device
 */
+ (void)setWhiteBalanceType:(WhiteBalanceType)type forDevice:(AVCaptureDevice *)device{
    NSError *error = nil;
    if ([device lockForConfiguration:&error]) {
        if (type == WhiteBalanceTypeAuto) {
            [device setWhiteBalanceMode:AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance];
            [device unlockForConfiguration];
            return;
        }
        AVCaptureWhiteBalanceGains currentGains =[device deviceWhiteBalanceGains];
        if (!currentGains.redGain || !currentGains.blueGain || !currentGains.greenGain) {
            [device unlockForConfiguration];
            return;
        }
        AVCaptureWhiteBalanceTemperatureAndTintValues tintValues = [device temperatureAndTintValuesForDeviceWhiteBalanceGains:currentGains];
        switch (type) {
            case WhiteBalanceTypeLamp:
                tintValues.temperature = 3000;
                break;
            case WhiteBalanceTypeFluorescent:
                tintValues.temperature = 4000;
                break;
            case WhiteBalanceTypeSunlight:
                tintValues.temperature = 5000;
                break;
            case WhiteBalanceTypeCloud:
                tintValues.temperature = 6000;
                break;
            case WhiteBalanceTypeShadow:
                tintValues.temperature = 7000;
                break;
            default:
                break;
        }
        
        AVCaptureWhiteBalanceGains newGains = [device deviceWhiteBalanceGainsForTemperatureAndTintValues:tintValues];
        if (@available(iOS 10.0, *)) {
            if ([device isLockingWhiteBalanceWithCustomDeviceGainsSupported]) {
                [device setWhiteBalanceModeLockedWithDeviceWhiteBalanceGains:newGains completionHandler:nil];
            }
        }
        [device unlockForConfiguration];
    }else {
        NSLog( @"Could not lock device for configuration: %@", error );
    }
}

+ (void)setWhiteBalance:(CGFloat)value normalized:(BOOL)normalized forDevice:(AVCaptureDevice *)device {
    NSError *error = nil;
    if ([device lockForConfiguration:&error]) {
        AVCaptureWhiteBalanceGains currentGains = device.deviceWhiteBalanceGains;
        if (!currentGains.blueGain || !currentGains.greenGain || !currentGains.redGain) {
            [device unlockForConfiguration];
            return;
        }
        
        AVCaptureWhiteBalanceTemperatureAndTintValues temperature = [device temperatureAndTintValuesForDeviceWhiteBalanceGains:currentGains];
        if (normalized) {
            //色温3000 - 8000
            temperature.temperature = 3000 + (value * 5) * 1000;
            NSLog(@"t = %f",temperature.temperature);
        } else {
            temperature.temperature = value;
        }
        AVCaptureWhiteBalanceGains gains = [device deviceWhiteBalanceGainsForTemperatureAndTintValues:temperature];
        
        if (gains.blueGain > device.maxWhiteBalanceGain) {
            gains.blueGain = 4;
        }
        if (gains.greenGain > device.maxWhiteBalanceGain) {
            gains.greenGain = 4;
        }
        if (gains.redGain > device.maxWhiteBalanceGain) {
            gains.redGain = 4;
        }
        if (gains.blueGain < 1) {
            gains.blueGain = 1;
        }
        if (gains.greenGain < 1) {
            gains.greenGain = 1;
        }
        if (gains.redGain < 1) {
            gains.redGain = 1;
        }
        
        if (@available(iOS 10.0, *)) {
            if ([device isLockingWhiteBalanceWithCustomDeviceGainsSupported]) {
                [device setWhiteBalanceModeLockedWithDeviceWhiteBalanceGains:gains completionHandler:^(CMTime syncTime) {
                    NSLog(@"set setWhiteBalanceModeLockedWithDeviceWhiteBalanceGains complete at time = %f",CMTimeGetSeconds(syncTime));
                }];
            } else {
                NSLog(@"device do not supported isLockingWhiteBalanceWithCustomDeviceGainsSupported");
            }
        } else {
            if ([device isWhiteBalanceModeSupported:(AVCaptureWhiteBalanceModeLocked)]) {
                [device setWhiteBalanceModeLockedWithDeviceWhiteBalanceGains:gains completionHandler:^(CMTime syncTime) {
                    NSLog(@"set setWhiteBalanceModeLockedWithDeviceWhiteBalanceGains complete at time = %f",CMTimeGetSeconds(syncTime));
                }];
            } else {
                NSLog(@"device do not supported AVCaptureWhiteBalanceModeLocked");
            }
        }
        
        [device unlockForConfiguration];
    } else {
        NSLog( @"Could not lock device for configuration: %@", error );
    }
}

/**
 手电筒

 @param torchOn 是否开启手电筒
 @param device device
 */
+ (void)setTorchOn:(BOOL)torchOn forDevice:(AVCaptureDevice *)device{
    AVCaptureTorchMode torchMode;
    if (torchOn) {
        torchMode = AVCaptureTorchModeOn;
    }else{
        torchMode = AVCaptureTorchModeOff;
    }
    
    if (device.hasTorch && [device isTorchModeSupported:torchMode] ) {
        NSError *error = nil;
        if ([device lockForConfiguration:&error]) {
            device.torchMode = torchMode;
            [device unlockForConfiguration];
        } else {
            NSLog( @"Could not lock device for configuration: %@", error );
        }
    }
}

+ (void)setTorchLevel:(CGFloat)value forDevice:(AVCaptureDevice *)device {
    NSError *error = nil;
    if (value == 0) {
        return;
    }
    if ([device lockForConfiguration:&error]) {
        if ([device hasTorch] && device.torchAvailable && [device isTorchModeSupported:(AVCaptureTorchModeOn)]) {
            [device setTorchModeOnWithLevel:value error:&error];
        }
        [device unlockForConfiguration];
    } else {
        NSLog( @"Could not lock device for configuration: %@", error );
    }
}

/**
 手电筒亮度

 @param value 亮度级别 0～1
 @param device device
 */
+ (void)setTorchValue:(CGFloat)value forDevice:(AVCaptureDevice *)device {
    if (device.hasTorch && device.torchMode == AVCaptureTorchModeOn && device.isTorchAvailable && device.isTorchActive) {
        NSError *error = nil;
        if ([device lockForConfiguration:&error]) {
            if (![device setTorchModeOnWithLevel:value error:&error]) {
                NSLog(@"Could not set device for torch level: %@",error);
            }
            [device unlockForConfiguration];
        } else {
            NSLog( @"Could not lock device for configuration: %@", error );

        }
    }
}


/**
 闪光灯

 @param flashOn 是否打开闪光灯
 @param device device
 */
+ (void)setFlashOn:(BOOL)flashOn forDevice:(AVCaptureDevice *)device{
    AVCaptureFlashMode flashMode;
    if (flashOn) {
        flashMode = AVCaptureFlashModeOn;
    }else{
        flashMode = AVCaptureFlashModeOff;
    }
    
    if (device.hasFlash && [device isFlashModeSupported:flashMode] ) {
        NSError *error = nil;
        if ([device lockForConfiguration:&error]) {
            device.flashMode = flashMode;
            [device unlockForConfiguration];
        }
        else {
            NSLog( @"Could not lock device for configuration: %@", error );
        }
    }
}

/**
 ISO和曝光时长
 */
+ (void)setISO:(CGFloat)iValue iType:(ISODurationType)iType iNor:(BOOL)iNor duration:(CGFloat)duration dType:(ISODurationType)dType dNor:(BOOL)dNor forDevice:(AVCaptureDevice *)device {
    NSError *error = nil;
    if ([device lockForConfiguration:&error]) {
        CGFloat customD = CMTimeGetSeconds(device.exposureDuration);
        CGFloat customISO = device.ISO;
        AVCaptureDeviceFormat *currentFormat = device.activeFormat;
        CGFloat maxD = CMTimeGetSeconds(currentFormat.maxExposureDuration);
        CGFloat minD = CMTimeGetSeconds(currentFormat.minExposureDuration);
        CGFloat maxISO = currentFormat.maxISO;
        CGFloat minISO = currentFormat.minISO;
        if (@available(iOS 12.0, *)) {
            CGFloat activeMaxD = CMTimeGetSeconds(device.activeMaxExposureDuration);
            if (maxD > activeMaxD) {
//                maxD = activeMaxD;
            }
//            NSLog(@"activeMaxD = %f",activeMaxD);
        }
        
        if (iNor) {
            iValue = minISO + iValue * (maxISO - minISO);
        }
       
        if (dNor) {
            duration = minD + duration * (maxD - minD);
        }
        
        if (iType == ISODurationTypeCustom) {
            iValue = customISO;
        } else if (iType == ISODurationTypeDefault) {
            iValue = AVCaptureISOCurrent;
        }
        
        if (dType == ISODurationTypeCustom) {
            duration = customD;
        }
        
        if (isnan(iValue) || isnan(duration)) {
            return;
        }
        
        if (iValue < minISO) {
            iValue = minISO;
        }
        
        if (iValue > maxISO) {
            iValue = maxISO;
        }
        
        if (duration < minD) {
            duration = minD;
        }
        
        if (duration > maxD) {
            duration = maxD;
        }
        
        NSLog(@"iso = %f,duration = %f",iValue,duration);
        CMTime ct = CMTimeMakeWithSeconds(duration, device.exposureDuration.timescale);
        if (dType == ISODurationTypeDefault) {
            ct = AVCaptureExposureDurationCurrent;
        }
        [device setExposureModeCustomWithDuration:ct ISO:iValue completionHandler:^(CMTime syncTime) {
            NSLog(@"set focus lens complete at time = %f",CMTimeGetSeconds(syncTime));
        }];
        
        device.subjectAreaChangeMonitoringEnabled = NO;
        [device unlockForConfiguration];
    } else {
        NSLog( @"Could not lock device for configuration: %@", error );
    }
}


/**
 某点 自动 对焦和曝光
 */
+ (void)setInterestPoint:(CGPoint)point focus:(BOOL)fEnable fAuto:(BOOL)fAuto exposure:(BOOL)eEnable eAuto:(BOOL)eAuto forDevice:(AVCaptureDevice *)device {
    NSError *error;
    if ([device lockForConfiguration:&error]) {
        
        device.subjectAreaChangeMonitoringEnabled = NO;
        if (fEnable) {
            if ([device isFocusPointOfInterestSupported]) {
                [device setFocusPointOfInterest:point];
            }
            if (fAuto) {
                if ([device isFocusModeSupported:(AVCaptureFocusModeContinuousAutoFocus)]) {
                    [device setFocusMode:(AVCaptureFocusModeAutoFocus)];
                }
                device.subjectAreaChangeMonitoringEnabled = YES;
            } else {
                if ([device isFocusModeSupported:(AVCaptureFocusModeLocked)]) {
                    [device setFocusMode:(AVCaptureFocusModeLocked)];
                }
            }
        }
        
        if (eEnable) {
            if ([device isExposurePointOfInterestSupported]){
                [device setExposurePointOfInterest:point];
            }
            if (eAuto) {
                if ([device isExposureModeSupported:(AVCaptureExposureModeContinuousAutoExposure)]) {
                    [device setExposureMode:(AVCaptureExposureModeContinuousAutoExposure)];
                }
                device.subjectAreaChangeMonitoringEnabled = YES;
            } else {
                if ([device isExposureModeSupported:AVCaptureExposureModeLocked]) {
                    [device setExposureMode:(AVCaptureExposureModeLocked)];
                }
            }
        }
        [device unlockForConfiguration];
    } else {
        NSLog( @"Could not lock device for configuration: %@", error );
    }
}


/**
 某点 锁定 对焦和曝光

 @param point 焦点
 @param device device
 */
+ (void)setLockInterestPointForFocusAndExposure:(CGPoint)point forDevice:(AVCaptureDevice *)device {
    NSError *error;
    if ([device lockForConfiguration:&error]) {
        if ([device isFocusPointOfInterestSupported] && [device isFocusModeSupported:AVCaptureFocusModeLocked]) {
            [device setFocusPointOfInterest:point];
            [device setFocusMode:AVCaptureFocusModeLocked];
        }
        if([device isExposurePointOfInterestSupported] && [device isExposureModeSupported:AVCaptureExposureModeLocked]){
            [device setExposurePointOfInterest:point];
            [device setExposureMode:AVCaptureExposureModeLocked];
        }
        device.subjectAreaChangeMonitoringEnabled = YES;
        [device unlockForConfiguration];
    } else {
        NSLog( @"Could not lock device for configuration: %@", error );
    }
}


/**
 自动对焦/曝光/白平很

 @param focus 对焦
 @param exposure 曝光
 @param whiteBalance 白平衡
 @param device device
 */
+ (void)setAutoFocus:(BOOL)focus exposure:(BOOL)exposure whiteBalance:(BOOL)whiteBalance forDevice:(AVCaptureDevice *)device{
    NSError *error = nil;
    if ( [device lockForConfiguration:&error] ) {
        if (focus) {
            if ([device isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus]) {
                [device setFocusMode:AVCaptureFocusModeContinuousAutoFocus];
            }
        }else{
            if ([device isFocusModeSupported:AVCaptureFocusModeLocked]) {
                [device setFocusMode:AVCaptureFocusModeLocked];
            }
        }
        if (exposure) {
            if([device isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure]){
                [device setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
            }
        }else{
            if([device isExposureModeSupported:AVCaptureExposureModeLocked]){
                [device setExposureMode:AVCaptureExposureModeLocked];
            }
        }
        if (whiteBalance) {
            if ([device isWhiteBalanceModeSupported:AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance]) {
                [device setWhiteBalanceMode:AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance];
            }
        }else{
            if ([device isWhiteBalanceModeSupported:AVCaptureWhiteBalanceModeLocked]) {
                [device setWhiteBalanceMode:AVCaptureWhiteBalanceModeLocked];
            }
        }
        device.subjectAreaChangeMonitoringEnabled = NO;
        [device unlockForConfiguration];
    }else{
        NSLog( @"Could not lock device for configuration: %@", error );
    }
}


/**
 焦距类型

 @param focusType 焦距类型
 @return 值
 */
+ (CGFloat)focusLenByType:(FocusType)focusType{
    CGFloat focusLen = 0;
    switch (focusType) {
        case FocusTypeAuto:
            break;
        case FocusTypeClose:
            focusLen = 0;
            break;
        case FocusTypeMedium:
            focusLen = 0.65;
            break;
        case FocusTypeFar:
            focusLen = 0.83;
            break;
        default:
            break;
    }
    return focusLen;
}


/**
 设置焦距

 @param focus 是否自动对焦
 @param focusType 对焦类型 值 0～1
 @param device device
 */
+ (void)setAutoFocus:(BOOL)focus focusType:(FocusType)focusType forDevice:(AVCaptureDevice *)device{
    NSError *error = nil;
    CGFloat focusLen = [self focusLenByType:focusType];
    if ( [device lockForConfiguration:&error] ) {
        if (focus) {
            if ([device isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus]) {
                [device setFocusMode:AVCaptureFocusModeContinuousAutoFocus];
            }
        }else{
            if ([device isFocusModeSupported:AVCaptureFocusModeLocked]) {
                [device setFocusModeLockedWithLensPosition:focusLen completionHandler:nil];
            }
        }
        device.subjectAreaChangeMonitoringEnabled = NO;
        [device unlockForConfiguration];
    }else{
        NSLog( @"Could not lock device for configuration: %@", error );
    }
}

//value 0~1 are supported ,default is 1 for the furest; 0 is shorttset
+ (void)setFocusLens:(CGFloat)value forDevice:(AVCaptureDevice *)device {
    NSError *error = nil;
    if ([device lockForConfiguration:&error]) {
        if (value < 0) {
            value = 0;
        }
        if (value > 1) {
            value = 1;
        }
        if ([device isFocusModeSupported:(AVCaptureFocusModeLocked)]) {
            [device setFocusModeLockedWithLensPosition:value completionHandler:^(CMTime syncTime) {
                NSLog(@"set focus lens complete at time = %f",CMTimeGetSeconds(syncTime));
            }];
        } else {
            NSLog( @"device Unsupported set LensPosition");
        }
        [device unlockForConfiguration];
    } else {
        NSLog( @"Could not lock device for configuration: %@", error );
    }
}



+ (void)setZoomFactor:(CGFloat)factor normalized:(BOOL)normalized forDevice:(AVCaptureDevice *)device {
    NSError *error = nil;
    
    if ( [device lockForConfiguration:&error] == YES ) {
        CGFloat aimFactor = factor;
        AVCaptureDeviceFormat *currentFormat = device.activeFormat;
        CGFloat maxFactor = currentFormat.videoMaxZoomFactor;
//        NSLog(@"maxFactor = %f",maxFactor);
        if (normalized) {
            aimFactor = 1 + aimFactor * (maxFactor - 1);
        }
        if (aimFactor > maxFactor) {
            aimFactor = maxFactor;
        }
        if (aimFactor < 1) {
            aimFactor = 1;
        }
        device.videoZoomFactor = aimFactor;
        
    }else{
        NSLog( @"Could not lock device for configuration: %@", error );
    }
}

+ (void)setBestFPSForDevice:(AVCaptureDevice *)device{
    if ( [device lockForConfiguration:nil] == YES ) {
        device.activeVideoMaxFrameDuration = device.activeVideoMinFrameDuration;
        NSLog(@"device.activeVideoMaxFrameDuration:CMTime(%lld,%d)",device.activeVideoMaxFrameDuration.value,device.activeVideoMaxFrameDuration.timescale);
        [device unlockForConfiguration];
    }
}

#pragma mark - Size
static BOOL moreThan2GB;
+ (BOOL)isMoreThan2GBMemory {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        moreThan2GB = [NSProcessInfo processInfo].physicalMemory > 2000000000;
    });
    return moreThan2GB;
}

+ (CGSize)getPreviewSizeFromSize:(CGSize)size {
    // 限制短边最大像素
    float maxPixel;
    BOOL moreThan2GB = [self.class isMoreThan2GBMemory];
    if (moreThan2GB) {
        maxPixel = 2000000.0;
    }else{
        maxPixel = 1500000.0;
    }
    return [self.class scaleSize:size withMaxPixel:maxPixel];
}

+ (CGSize)getDraftSizeFromSize:(CGSize)size {
    return [self.class scaleSize:size withMaxPixel:600*600];
}

+ (CGSize)getDeviceSizeFromDevice:(AVCaptureDevice *)device {
    CMVideoDimensions currentSize = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription);
    return CGSizeMake(currentSize.width, currentSize.height);;
}

+ (CGSize)setBestVideoSizeFormatForDevice:(AVCaptureDevice *)device{
    
    CGFloat targetRatio = round(16.f/9.f * 10)/10;
    
    // bestFormat
    AVCaptureDeviceFormat *bestFormat = nil;
    for (AVCaptureDeviceFormat *format in device.formats) {
        CMVideoDimensions size = CMVideoFormatDescriptionGetDimensions(format.formatDescription);
        CGFloat currentRatio = round(size.width/(CGFloat)size.height * 10)/10;
        
        FourCharCode mediaSubTypeChar = CMFormatDescriptionGetMediaSubType(format.formatDescription);
        NSString *mediaSubType = [NSString stringWithFormat:@"%c",(unsigned int)mediaSubTypeChar];
        
//        NSLog(@"%@",format);
        if ([UIScreen mainScreen].bounds.size.height/ [UIScreen mainScreen].bounds.size.width > 3.0/2.0) { // !4s
            if (size.width*size.height >= 1920*1080 && currentRatio == targetRatio && [mediaSubType isEqualToString:@"f"]) {
                bestFormat = format;
                break;
            }
        }
    }
    
    if (!bestFormat) {
        for (AVCaptureDeviceFormat *format in device.formats.reverseObjectEnumerator) {
            CMVideoDimensions size = CMVideoFormatDescriptionGetDimensions(format.formatDescription);
            CGFloat currentRatio = round(size.width/(CGFloat)size.height * 10)/10;
            
            FourCharCode mediaSubTypeChar = CMFormatDescriptionGetMediaSubType(format.formatDescription);
            NSString *mediaSubType = [NSString stringWithFormat:@"%c",(unsigned int)mediaSubTypeChar];
            
            if (currentRatio == targetRatio && [mediaSubType isEqualToString:@"f"]) {
                bestFormat = format;
                break;
            }
        }
    }
    
    // set bestFormat
    if (bestFormat) {
        NSError *error = nil;
        if ([device lockForConfiguration:&error]) {
            device.activeFormat = bestFormat;
            device.activeVideoMaxFrameDuration = device.activeVideoMinFrameDuration;
            [device unlockForConfiguration];
            
            CMVideoDimensions bestSize = CMVideoFormatDescriptionGetDimensions(bestFormat.formatDescription);
            CGSize targetSize = CGSizeMake(bestSize.width, bestSize.height);
            return targetSize;
        }else{
            NSLog( @"Could not lock device for configuration: %@", error );
        }
    }
    
    // set failed
    NSLog(@"Can't get the bestFormat");
    
    return CGSizeMake(1920, 1080);
}

+ (CGSize)scaleSize:(CGSize)size withMaxPixel:(CGFloat)maxPixel {
    if (size.width * size.height > maxPixel) {
        float scale = sqrt(maxPixel/(size.width*size.height));
        size = CGSizeMake(round(size.width*scale), round(size.height*scale));
    }
    
    // 宽高都取偶数
    int wid = (int)size.width;
    if (wid%2) {
        wid++;
    }
    int hei = (int)size.height;
    if (hei%2) {
        hei++;
    }
    size = CGSizeMake(wid, hei);
    return size;
}

#pragma mark - Orientation
+ (UIImageOrientation)realImageOriWithDevideOri:(UIDeviceOrientation)ori devicePosition:(AVCaptureDevicePosition)devicePosition{
    UIImageOrientation imageOrientation;
    if (devicePosition == AVCaptureDevicePositionBack) {
        switch(ori){
            case UIDeviceOrientationPortrait:
                imageOrientation = UIImageOrientationRight;
                break;
            case UIDeviceOrientationLandscapeLeft:
                imageOrientation = UIImageOrientationUp;
                break;
            case UIDeviceOrientationLandscapeRight:
                imageOrientation = UIImageOrientationDown;
                break;
            case UIDeviceOrientationPortraitUpsideDown:
                imageOrientation = UIImageOrientationLeft;
                break;
            default:
                imageOrientation = UIImageOrientationUp;
                break;
        }
    }else{
        switch(ori){
            case UIDeviceOrientationPortrait:
                imageOrientation = UIImageOrientationLeftMirrored;
                break;
            case UIDeviceOrientationLandscapeLeft:
                imageOrientation = UIImageOrientationDownMirrored;
                break;
            case UIDeviceOrientationLandscapeRight:
                imageOrientation = UIImageOrientationUpMirrored;
                break;
            case UIDeviceOrientationPortraitUpsideDown:
                imageOrientation = UIImageOrientationRight;
                break;
            default:
                imageOrientation = UIImageOrientationLeftMirrored;
                break;
        }
    }
    
    return imageOrientation;
}

#pragma mark -
#pragma mark - Getter
- (AVCaptureDevicePosition)devicePosition {
    AVCaptureDevicePosition currentPosition = AVCaptureDevicePositionFront;
    NSNumber *userPosition = [[NSUserDefaults standardUserDefaults] objectForKey:@"USER_CAMERA_POSITON"];
    if (userPosition && userPosition.intValue == AVCaptureDevicePositionBack) {
        currentPosition = AVCaptureDevicePositionBack;
    }
    return currentPosition;
}

- (void)setDevicePosition:(AVCaptureDevicePosition)devicePosition {
    [[NSUserDefaults standardUserDefaults] setObject:@(devicePosition) forKey:@"USER_CAMERA_POSITON"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (AVCaptureSession *)session {
    if (!_session) {
        _session = [[AVCaptureSession alloc] init];
    }
    return _session;
}

- (AVCaptureDeviceInput *)deviceInput {
    if (!_deviceInput) {
        NSError *error = nil;
        _deviceInput = [AVCaptureDeviceInput deviceInputWithDevice:[self.class findDeviceWithPosition:(AVCaptureDevicePositionBack) useDepth:NO] error:&error];
    }
    return _deviceInput;
}

- (AVCaptureDevice *)inputDevice {
    if (!_inputDevice) {
        _inputDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    }
    return _inputDevice;
}

- (AVCaptureStillImageOutput *)stillImageOutput {
    if (!_stillImageOutput) {
        _stillImageOutput = [[AVCaptureStillImageOutput alloc] init];
        [_stillImageOutput setOutputSettings:[self getDefaultPixelFormat]];
    }
    return _stillImageOutput;
}

- (AVCapturePhotoOutput *)photoOutput  API_AVAILABLE(ios(10.0)){
    if (!_photoOutput) {
        _photoOutput = [[AVCapturePhotoOutput alloc] init];
    }
    return _photoOutput;
}

- (AVCaptureVideoDataOutput *)videoOutput {
    if (!_videoOutput) {
        _videoOutput = [[AVCaptureVideoDataOutput alloc] init];
        _videoOutput.alwaysDiscardsLateVideoFrames = YES;
        [_videoOutput setVideoSettings:[self getDefaultPixelFormat]];
        [_videoOutput setSampleBufferDelegate:self queue:self.outputProcessQueue];
    }
    return _videoOutput;
}

- (AVCaptureMetadataOutput *)metadataOutput {
    if (!_metadataOutput) {
        _metadataOutput = [[AVCaptureMetadataOutput alloc] init];
        [_metadataOutput setMetadataObjectsDelegate:self queue:self.metadataProcessQueue];
    }
    return _metadataOutput;
}

- (NSDictionary *)getDefaultPixelFormat {
    NSDictionary *dict = @{
                           (id)kCVPixelBufferPixelFormatTypeKey : [NSNumber numberWithInt:kCVPixelFormatType_32BGRA],
                           };
    return dict;
}

- (AVCaptureAudioDataOutput *)audioOutput {
    if (!_audioOutput) {
        _audioOutput = [[AVCaptureAudioDataOutput alloc] init];
    }
    return _audioOutput;
}

- (AVCaptureDepthDataOutput *)depthOutput  API_AVAILABLE(ios(11.0)){
    if (!_depthOutput) {
        _depthOutput = [[AVCaptureDepthDataOutput alloc] init];
        _depthOutput.alwaysDiscardsLateDepthData = YES;
        _depthOutput.filteringEnabled = YES;
        [_depthOutput setDelegate:self callbackQueue:self.outputProcessQueue];
    }
    return _depthOutput;
}

- (dispatch_queue_t)outputProcessQueue {
    if (!_outputProcessQueue) {
        _outputProcessQueue = dispatch_queue_create("CameraDepthDataProcess_SerialQueue", DISPATCH_QUEUE_SERIAL);
    }
    return _outputProcessQueue;
}

- (dispatch_queue_t)metadataProcessQueue {
    if (!_metadataProcessQueue) {
        _metadataProcessQueue = dispatch_queue_create("CameraMetaDataProcess_SerialQueue",  DISPATCH_QUEUE_SERIAL);
    }
    return _metadataProcessQueue;
}

- (AVCaptureDataOutputSynchronizer *)depthSynchronizer  API_AVAILABLE(ios(11.0)){
    if (!_depthSynchronizer) {
        _depthSynchronizer = [[AVCaptureDataOutputSynchronizer alloc] initWithDataOutputs:@[self.videoOutput,self.depthOutput]];
    }
    return _depthSynchronizer;
}

#pragma mark -
#pragma mark - GPUImage Relate

- (void)addTarget:(id<GPUImageInput>)newTarget atTextureLocation:(NSInteger)textureLocation {
    [super addTarget:newTarget atTextureLocation:textureLocation];
    [newTarget setInputRotation:outputRotation atIndex:textureLocation];
}

- (void)updateOrientationSendToTargets {
    runSynchronouslyOnVideoProcessingQueue(^{
        if ([self devicePosition] == AVCaptureDevicePositionBack)
        {
            if (_horizontallyMirrorRearFacingCamera)
            {
                switch(_outputImageOrientation)
                {
                    case UIInterfaceOrientationPortrait:outputRotation = kGPUImageRotateRightFlipVertical; break;
                    case UIInterfaceOrientationPortraitUpsideDown:outputRotation = kGPUImageRotate180; break;
                    case UIInterfaceOrientationLandscapeLeft:outputRotation = kGPUImageFlipHorizonal; break;
                    case UIInterfaceOrientationLandscapeRight:outputRotation = kGPUImageFlipVertical; break;
                    default:outputRotation = kGPUImageNoRotation;
                }
            }
            else
            {
                switch(_outputImageOrientation)
                {
                    case UIInterfaceOrientationPortrait:outputRotation = kGPUImageRotateRight; break;
                    case UIInterfaceOrientationPortraitUpsideDown:outputRotation = kGPUImageRotateLeft; break;
                    case UIInterfaceOrientationLandscapeLeft:outputRotation = kGPUImageRotate180; break;
                    case UIInterfaceOrientationLandscapeRight:outputRotation = kGPUImageNoRotation; break;
                    default:outputRotation = kGPUImageNoRotation;
                }
            }
        }
        else
        {
            if (_horizontallyMirrorFrontFacingCamera)
            {
                switch(_outputImageOrientation)
                {
                    case UIInterfaceOrientationPortrait:outputRotation = kGPUImageRotateRightFlipVertical; break;
                    case UIInterfaceOrientationPortraitUpsideDown:outputRotation = kGPUImageRotateRightFlipHorizontal; break;
                    case UIInterfaceOrientationLandscapeLeft:outputRotation = kGPUImageFlipHorizonal; break;
                    case UIInterfaceOrientationLandscapeRight:outputRotation = kGPUImageFlipVertical; break;
                    default:outputRotation = kGPUImageNoRotation;
                }
            }
            else
            {
                switch(_outputImageOrientation)
                {
                    case UIInterfaceOrientationPortrait:outputRotation = kGPUImageRotateRight; break;
                    case UIInterfaceOrientationPortraitUpsideDown:outputRotation = kGPUImageRotateLeft; break;
                    case UIInterfaceOrientationLandscapeLeft:outputRotation = kGPUImageNoRotation; break;
                    case UIInterfaceOrientationLandscapeRight:outputRotation = kGPUImageRotate180; break;
                    default:outputRotation = kGPUImageNoRotation;
                }
            }
        }
        
        for (id<GPUImageInput> currentTarget in targets)
        {
            NSInteger indexOfObject = [targets indexOfObject:currentTarget];
            [currentTarget setInputRotation:outputRotation atIndex:[[targetTextureIndices objectAtIndex:indexOfObject] integerValue]];
        }
    });
}

- (void)setOutputImageOrientation:(UIInterfaceOrientation)newValue {
    _outputImageOrientation = newValue;
    [self updateOrientationSendToTargets];
}

- (void)setHorizontallyMirrorFrontFacingCamera:(BOOL)newValue {
    _horizontallyMirrorFrontFacingCamera = newValue;
    [self updateOrientationSendToTargets];
}

- (void)setHorizontallyMirrorRearFacingCamera:(BOOL)newValue {
    _horizontallyMirrorRearFacingCamera = newValue;
    [self updateOrientationSendToTargets];
}

@end
