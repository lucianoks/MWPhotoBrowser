//
//  MWPhoto.m
//  MWPhotoBrowser
//
//  Created by Michael Waterfall on 17/10/2010.
//  Copyright 2010 d3i. All rights reserved.
//

#import <SDWebImage/SDWebImageDecoder.h>
#import <SDWebImage/SDWebImageManager.h>
#import <SDWebImage/SDWebImageOperation.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import "MWPhoto.h"
#import "MWPhotoBrowser.h"

@interface MWPhoto () {

    BOOL _loadingInProgress;
    id <SDWebImageOperation> _webImageOperation;
    PHImageRequestID _assetRequestID;
        
}

@property (nonatomic, strong) UIImage *image;
@property (nonatomic, strong) NSURL *photoURL;
@property (nonatomic, strong) PHAsset *asset;
@property (nonatomic) CGSize assetTargetSize;

// Live photos
@property (nonatomic) PHLivePhoto *livePhoto;
@property (nonatomic) NSArray *livePhotoURLs;
@property (nonatomic) NSURL *livePhotoFirstFileURL;
@property (nonatomic) NSURL *livePhotoSecondFileURL;
@property (nonatomic) BOOL didDownloadLivePhotoFirstFile;
@property (nonatomic) BOOL didDownloadLivePhotoSecondFile;

- (void)imageLoadingComplete;

@end

@implementation MWPhoto

//--------------------------------------------------------------------------------------------------
#pragma mark - Class Methods

+ (MWPhoto *)photoWithImage:(UIImage *)image {
	return [[MWPhoto alloc] initWithImage:image];
}

+ (MWPhoto *)photoWithURL:(NSURL *)url {
    return [[MWPhoto alloc] initWithURL:url];
}

+ (MWPhoto *)photoWithAsset:(PHAsset *)asset targetSize:(CGSize)targetSize {
    return [[MWPhoto alloc] initWithAsset:asset targetSize:targetSize];
}

+ (MWPhoto *)videoWithURL:(NSURL *)url {
    return [[MWPhoto alloc] initWithVideoURL:url];
}

+ (MWPhoto *)photoWithLivePhotoURLs:(NSArray *)URLs {
    return [[MWPhoto alloc] initWithLivePhotoURLs:URLs];
}

//--------------------------------------------------------------------------------------------------
#pragma mark - Init

- (id)init {
    if ((self = [super init])) {
        self.emptyImage = YES;
    }
    return self;
}

- (id)initWithImage:(UIImage *)image {
    if ((self = [super init])) {
        self.image = image;
    }
    return self;
}

- (id)initWithURL:(NSURL *)url {
    if ((self = [super init])) {
        self.photoURL = url;
    }
    return self;
}

- (id)initWithAsset:(PHAsset *)asset targetSize:(CGSize)targetSize {
    if ((self = [super init])) {
        self.asset = asset;
        self.assetTargetSize = targetSize;
        self.isVideo = asset.mediaType == PHAssetMediaTypeVideo;
    }
    return self;
}

- (id)initWithVideoURL:(NSURL *)url {
    if ((self = [super init])) {
        self.videoURL = url;
        self.isVideo = YES;
        self.emptyImage = YES;
    }
    return self;
}

- (id)initWithLivePhotoURLs:(NSArray *)URLs {
    if (self = [super init]) {
        self.isLivePhoto = YES;
        self.livePhotoURLs = URLs;
    }
    return self;
}

//--------------------------------------------------------------------------------------------------
#pragma mark - Video

- (void)setVideoURL:(NSURL *)videoURL {
    _videoURL = videoURL;
    self.isVideo = YES;
}

- (void)getVideoURL:(void (^)(NSURL *url))completion {
    if (_videoURL) {
        completion(_videoURL);
    } else if (_asset && _asset.mediaType == PHAssetMediaTypeVideo) {
        PHVideoRequestOptions *options = [PHVideoRequestOptions new];
        options.networkAccessAllowed = YES;
        [[PHImageManager defaultManager] requestAVAssetForVideo:_asset options:options resultHandler:^(AVAsset *asset, AVAudioMix *audioMix, NSDictionary *info) {
            if ([asset isKindOfClass:[AVURLAsset class]]) {
                completion(((AVURLAsset *)asset).URL);
            } else {
                completion(nil);
            }
        }];
    }
    return completion(nil);
}

//--------------------------------------------------------------------------------------------------
#pragma mark - MWPhoto Protocol Methods

- (void)loadUnderlyingImageAndNotify {
    NSAssert([[NSThread currentThread] isMainThread], @"This method must be called on the main thread.");
    if (_loadingInProgress) return;
    _loadingInProgress = YES;
    @try {
        if (self.underlyingImage) {
            [self imageLoadingComplete];
        } else {
            [self performLoadUnderlyingImageAndNotify];
        }
    }
    @catch (NSException *exception) {
        self.underlyingImage = nil;
        _loadingInProgress = NO;
        [self imageLoadingComplete];
    }
    @finally {
    }
}

// Set the underlyingImage
- (void)performLoadUnderlyingImageAndNotify {
    
    // Get underlying image
    if (_image) {
        
        // We have UIImage!
        self.underlyingImage = _image;
        [self imageLoadingComplete];
        
    } else if (_photoURL) {
        
        // Check what type of url it is
        if ([[[_photoURL scheme] lowercaseString] isEqualToString:@"assets-library"]) {
            
            // Load from assets library
            [self _performLoadUnderlyingImageAndNotifyWithAssetsLibraryURL: _photoURL];
            
        } else if ([_photoURL isFileReferenceURL]) {
            
            // Load from local file async
            [self _performLoadUnderlyingImageAndNotifyWithLocalFileURL: _photoURL];
            
        } else {
            
            // Load async from web (using SDWebImage)
            [self _performLoadUnderlyingImageAndNotifyWithWebURL: _photoURL];
            
        }
        
    } else if (_asset) {
        
        // Load from photos asset
        [self _performLoadUnderlyingImageAndNotifyWithAsset: _asset targetSize:_assetTargetSize];
        
    } else {
        
        // Image is empty
        [self imageLoadingComplete];
        
    }
}

//--------------------------------------------------------------------------------------------------
#pragma mark - MWPhoto protocol methods for Live Photos

- (void)loadUnderlyingLivePhotoAndNotify {
    
    BOOL isMainThread = [[NSThread currentThread] isMainThread];
    NSAssert(isMainThread, @"This method must be called on the main thread.");
    
    if (_loadingInProgress) {
        return;
    }
    
    _loadingInProgress = YES;
    
    @try {
        if (self.underlyingLivePhoto) {
            [self livePhotoLoadingComplete];
        } else {
            [self performLoadUnderlyingLivePhotoAndNotify];
        }
    }
    @catch (NSException *exception) {
        self.underlyingLivePhoto = nil;
        _loadingInProgress = NO;
        [self livePhotoLoadingComplete];
    }
    @finally {
        
    }
}

- (void)performLoadUnderlyingLivePhotoAndNotify {
    if (self.livePhoto) {
        self.underlyingLivePhoto = self.livePhoto;
        [self livePhotoLoadingComplete];
    } else if (self.livePhotoURLs) {
        [self _performLoadUnderlyingLivePhotoAndNotifyWithWebURLs:self.livePhotoURLs];
    }
}

//--------------------------------------------------------------------------------------------------
#pragma mark - Utils

// Load from local file
- (void)_performLoadUnderlyingImageAndNotifyWithWebURL:(NSURL *)url {
    @try {
        SDWebImageManager *manager = [SDWebImageManager sharedManager];
        _webImageOperation = [manager downloadImageWithURL:url
                                                   options:0
                                                  progress:^(NSInteger receivedSize, NSInteger expectedSize) {
                                                      if (expectedSize > 0) {
                                                          float progress = receivedSize / (float)expectedSize;
                                                          NSDictionary* dict = [NSDictionary dictionaryWithObjectsAndKeys:
                                                                                [NSNumber numberWithFloat:progress], @"progress",
                                                                                self, @"photo", nil];
                                                          [[NSNotificationCenter defaultCenter] postNotificationName:MWPHOTO_PROGRESS_NOTIFICATION object:dict];
                                                      }
                                                  }
                                                 completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
                                                     if (error) {
                                                         MWLog(@"SDWebImage failed to download image: %@", error);
                                                     }
                                                     _webImageOperation = nil;
                                                     self.underlyingImage = image;
                                                     dispatch_async(dispatch_get_main_queue(), ^{
                                                         [self imageLoadingComplete];
                                                     });
                                                 }];
    } @catch (NSException *e) {
        MWLog(@"Photo from web: %@", e);
        _webImageOperation = nil;
        [self imageLoadingComplete];
    }
}

// Load from local file
- (void)_performLoadUnderlyingImageAndNotifyWithLocalFileURL:(NSURL *)url {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @autoreleasepool {
            @try {
                self.underlyingImage = [UIImage imageWithContentsOfFile:url.path];
                if (!_underlyingImage) {
                    MWLog(@"Error loading photo from path: %@", url.path);
                }
            } @finally {
                [self performSelectorOnMainThread:@selector(imageLoadingComplete) withObject:nil waitUntilDone:NO];
            }
        }
    });
}

// Load from asset library async
- (void)_performLoadUnderlyingImageAndNotifyWithAssetsLibraryURL:(NSURL *)url {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @autoreleasepool {
            @try {
                ALAssetsLibrary *assetslibrary = [[ALAssetsLibrary alloc] init];
                [assetslibrary assetForURL:url
                               resultBlock:^(ALAsset *asset){
                                   ALAssetRepresentation *rep = [asset defaultRepresentation];
                                   CGImageRef iref = [rep fullScreenImage];
                                   if (iref) {
                                       self.underlyingImage = [UIImage imageWithCGImage:iref];
                                   }
                                   [self performSelectorOnMainThread:@selector(imageLoadingComplete) withObject:nil waitUntilDone:NO];
                               }
                              failureBlock:^(NSError *error) {
                                  self.underlyingImage = nil;
                                  MWLog(@"Photo from asset library error: %@",error);
                                  [self performSelectorOnMainThread:@selector(imageLoadingComplete) withObject:nil waitUntilDone:NO];
                              }];
            } @catch (NSException *e) {
                MWLog(@"Photo from asset library error: %@", e);
                [self performSelectorOnMainThread:@selector(imageLoadingComplete) withObject:nil waitUntilDone:NO];
            }
        }
    });
}

// Load from photos library
- (void)_performLoadUnderlyingImageAndNotifyWithAsset:(PHAsset *)asset targetSize:(CGSize)targetSize {
    
    PHImageManager *imageManager = [PHImageManager defaultManager];
    
    PHImageRequestOptions *options = [PHImageRequestOptions new];
    options.networkAccessAllowed = YES;
    options.resizeMode = PHImageRequestOptionsResizeModeFast;
    options.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;
    options.synchronous = false;
    options.progressHandler = ^(double progress, NSError *error, BOOL *stop, NSDictionary *info) {
        NSDictionary* dict = [NSDictionary dictionaryWithObjectsAndKeys:
                              [NSNumber numberWithDouble: progress], @"progress",
                              self, @"photo", nil];
        [[NSNotificationCenter defaultCenter] postNotificationName:MWPHOTO_PROGRESS_NOTIFICATION object:dict];
    };
    
    _assetRequestID = [imageManager requestImageForAsset:asset targetSize:targetSize contentMode:PHImageContentModeAspectFit options:options resultHandler:^(UIImage *result, NSDictionary *info) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.underlyingImage = result;
            [self imageLoadingComplete];
        });
    }];

}

- (void)_performLoadUnderlyingLivePhotoAndNotifyWithWebURLs:(NSArray *)URLs {
    
    if (URLs.count != 2) {
        MWLog(@"Error: URLs must have one movie and one image URLs.");
        return;
    }
    
    NSURL *firstURL = URLs[0];
    NSURL *secondURL = URLs[1];
    
    NSURLSession *session = [NSURLSession sharedSession];
    
    NSString *tmpPath = [NSString stringWithFormat:@"file://%@", NSTemporaryDirectory()];
    NSString *tmpFirstFileName = [NSString stringWithFormat:@"%@.mov", [[NSUUID new] UUIDString]];
    NSString *tmpSecondFileName = [NSString stringWithFormat:@"%@.jpg", [[NSUUID new] UUIDString]];
    
    self.livePhotoFirstFileURL = [[NSURL URLWithString:tmpPath]
                                  URLByAppendingPathComponent:tmpFirstFileName];
    self.livePhotoSecondFileURL = [[NSURL URLWithString:tmpPath]
                                   URLByAppendingPathComponent:tmpSecondFileName];
    
    [session downloadTaskWithURL:firstURL completionHandler:
     ^(NSURL * _Nullable location, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        
         if (error) {
             MWLog(@"Error downloading Live Photo movie: %@", error);
             return;
         }
         
         MWLog(@"Live Photo movie downloaded.");
         
         NSError *err = nil;
         
         if (![[NSFileManager defaultManager]
               moveItemAtURL:location
               toURL:self.livePhotoFirstFileURL
               error:&err]) {
             MWLog(@"Error moving Live Photo movie: %@", err);
             return;
         }
         
         self.didDownloadLivePhotoFirstFile = YES;
         [self didDownloadLivePhotoAsset];
     }];
    
    [session downloadTaskWithURL:secondURL completionHandler:
     ^(NSURL * _Nullable location, NSURLResponse * _Nullable response, NSError * _Nullable error) {
         
         if (error) {
             MWLog(@"Error downloading Live Photo image: %@", error);
             return;
         }
         
         MWLog(@"Live Photo image downloaded.");
         
         NSError *err = nil;
         
         if (![[NSFileManager defaultManager]
               moveItemAtURL:location
               toURL:self.livePhotoSecondFileURL
               error:&err]) {
             MWLog(@"Error moving Live Photo image: %@", err);
             return;
         }
         
         self.didDownloadLivePhotoSecondFile = YES;
         [self didDownloadLivePhotoAsset];
     }];
}

- (void)didDownloadLivePhotoAsset {
    
    if (self.didDownloadLivePhotoFirstFile && self.didDownloadLivePhotoSecondFile) {
        NSArray *fileURLs = @[self.livePhotoFirstFileURL, self.livePhotoSecondFileURL];
        [PHLivePhoto
         requestLivePhotoWithResourceFileURLs:fileURLs
         placeholderImage:nil
         targetSize:CGSizeZero
         contentMode:PHImageContentModeAspectFill
         resultHandler:^(PHLivePhoto * _Nullable livePhoto, NSDictionary * _Nonnull info) {
             
             NSError *error;
             if ((error = info[PHLivePhotoInfoErrorKey])) {
                 MWLog(@"Error creating Live Photo: %@", value);
                 return;
             }
             
             NSNumber *isDegraded = info[PHLivePhotoInfoIsDegradedKey];
             
             MWLog(@"Live Photo created with PHLivePhotoInfoIsDegradedKey: %@", isDegraded);
             
             self.underlyingLivePhoto = livePhoto;
             [self livePhotoLoadingComplete];
         }];
    }
}

// Release if we can get it again from path or url
- (void)unloadUnderlyingImage {
    _loadingInProgress = NO;
	self.underlyingImage = nil;
}

- (void)imageLoadingComplete {
    NSAssert([[NSThread currentThread] isMainThread], @"This method must be called on the main thread.");
    // Complete so notify
    _loadingInProgress = NO;
    // Notify on next run loop
    [self performSelector:@selector(postCompleteNotification) withObject:nil afterDelay:0];
}

- (void)livePhotoLoadingComplete {
    NSAssert([[NSThread currentThread] isMainThread], @"This method must be called on the main thread.");
    
    _loadingInProgress = NO;
    [self performSelector:@selector(postLivePhotoCompleteNotification) withObject:nil afterDelay:0];
}

- (void)postCompleteNotification {
    [[NSNotificationCenter defaultCenter] postNotificationName:MWPHOTO_LOADING_DID_END_NOTIFICATION
                                                        object:self];
}

- (void)postLivePhotoCompleteNotification {
    [[NSNotificationCenter defaultCenter]
     postNotificationName:MWPHOTO_LIVE_PHOTO_LOADING_DID_END_NOTIFICATION
     object:self];
}

- (void)cancelAnyLoading {
    if (_webImageOperation != nil) {
        [_webImageOperation cancel];
        _loadingInProgress = NO;
    } else if (_assetRequestID != PHInvalidImageRequestID) {
        [[PHImageManager defaultManager] cancelImageRequest:_assetRequestID];
        _assetRequestID = PHInvalidImageRequestID;
    }
}

@end
