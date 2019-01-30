//
//  HXPhotoBrowserViewController.m
//  HXPhotoBrowser
//
//  Created by suin on 2018/8/15.
//  Copyright © 2018年 韩旭. All rights reserved.
//

#import "HXPhotoBrowserViewController.h"
#import "HXPhotoImageView.h"
#import "HXUIImageView+SDWebImage.h"
#import "HXPhotoBrowserMacro.h"
#import "HXPhotoHelper.h"
#import <pthread.h>

typedef NS_ENUM(NSInteger,PhotoCount){
    PhotoCountSingle,
    PhotoCountMultiple
};

@interface HXPhotoBrowserViewController ()<UIGestureRecognizerDelegate,UIScrollViewDelegate>
@property (nonatomic, strong) UIVisualEffectView *effectView;
@property (nonatomic, strong) HXPhotoImageView *currentImageView;
@property (nonatomic, strong) UIScrollView *photoScrollView;
@property (nonatomic, strong) NSArray <NSURL *>*urlArray;
@property (nonatomic, strong) NSArray *heightArray;
@property (nonatomic, strong) NSMutableArray *imageViewArray;
@property (nonatomic, assign) BOOL isCanPan;
@property (nonatomic, assign) CGFloat panStartY;
@property (nonatomic, assign) CGFloat panEndY;
@property (nonatomic, assign) CGFloat panMoveY;
@property (nonatomic, assign) PhotoCount photoCount;
@property (nonatomic, assign) CGFloat pageWidth;
@end

@implementation HXPhotoBrowserViewController


- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self setEffectView];
    _isCanPan = YES;
}

- (void)setEffectView{
    UIBlurEffect *blurEffect =[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    _effectView =[[UIVisualEffectView alloc]initWithEffect:blurEffect];
    _effectView.frame = CGRectMake(0, 0, kHXSCREEN_WIDTH, kHXSCREEN_HEIGHT);
    [self.view addSubview:_effectView];
}

- (void)setPhotoScrollView{
    UIWindow *window = [[UIApplication sharedApplication].windows lastObject];
    
    _photoScrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, kHXSCREEN_WIDTH + kHXPhotoBrowserPageMargin, kHXSCREEN_HEIGHT)];
    [window addSubview:_photoScrollView];
    _photoScrollView.backgroundColor = [UIColor clearColor];
    _photoScrollView.showsVerticalScrollIndicator = NO;
    _photoScrollView.showsHorizontalScrollIndicator = NO;
    _photoScrollView.pagingEnabled = YES;
    _photoScrollView.delegate = self;
    _photoScrollView.contentSize = CGSizeMake(self.photoCount == PhotoCountMultiple ? (kHXSCREEN_WIDTH + kHXPhotoBrowserPageMargin) * _urlArray.count : kHXSCREEN_WIDTH * _urlArray.count, kHXSCREEN_HEIGHT);
    
    [self addGesture];
    [self creatPhotoImageView];
}

- (void)creatPhotoImageView{
    self.photoScrollView.contentOffset = CGPointMake(_currentIndex ? _currentIndex * self.pageWidth : 0, 0);
    
    _imageViewArray = [NSMutableArray arrayWithCapacity:_urlArray.count];
    for (int i = 0; i < _urlArray.count; i ++) {
        [_imageViewArray addObject:[UIView new]];
    }
    
    _currentIndex = _currentIndex ? : 0;
    SDWebImageManager *manager = [SDWebImageManager sharedManager];
    [manager diskImageExistsForURL:self.urlArray[_currentIndex] completion:^(BOOL isInCache) {
        HXPhotoImageView *currentImageView = [[HXPhotoImageView alloc] initWithFrame:CGRectMake(self.currentIndex ? self.currentIndex * self.pageWidth : 0, 0, kHXSCREEN_WIDTH, kHXSCREEN_HEIGHT)];
        [self.photoScrollView addSubview:currentImageView];
        self.currentImageView = currentImageView;
        if (self.imageViewArray.count > 1) {
            [self setIndexTitleWithImgView:self.currentImageView withIndex:self.currentIndex];
        }
        if (isInCache) {
            [self photoInCache];
        } else{
            [self photoNotInCache];
        }
        self.imageViewArray[self.currentIndex] = currentImageView;
    }];
}

- (void)photoNotInCache{
    __weak __typeof(self)weakSelf = self;
    [self.currentImageView.imageView sd_setImageWithURL:self.urlArray[self.currentIndex] placeholderImage:[self getSelectedImg] options:SDWebImageRetryFailed progress:^(NSInteger receivedSize, NSInteger expectedSize, NSURL * _Nullable targetURL) {
        __strong __typeof(weakSelf)strongSelf = weakSelf;
        strongSelf.currentImageView.expectedSize = (CGFloat)expectedSize;
        strongSelf.currentImageView.receivedSize = (CGFloat)receivedSize;
    } completed:^(UIImage * _Nullable image, NSError * _Nullable error, SDImageCacheType cacheType, NSURL * _Nullable imageURL) {
        __strong __typeof(weakSelf)strongSelf = weakSelf;
        
        [strongSelf.currentImageView finishProcess];
        
        [strongSelf fetchOtherPhotos];
    }];
}

- (void)photoInCache{
    self.currentImageView.imageView.frame = [self getStartRect];
    [self.currentImageView finishProcess];
    [self.currentImageView.imageView sd_setImageWithURL:self.urlArray[self.currentIndex] placeholderImage:nil options:SDWebImageRetryFailed];
    [self transitionAnimation];
    [self fetchOtherPhotos];
}

- (void)fetchOtherPhotos{
    [_urlArray enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if (idx != self.currentIndex ? : 0) {
            HXPhotoImageView *imageView = [[HXPhotoImageView alloc] initWithFrame:CGRectMake(idx * self.pageWidth, 0, kHXSCREEN_WIDTH, kHXSCREEN_HEIGHT)];
            [self.photoScrollView addSubview:imageView];
            imageView.imageView.frame = [self getNewRectWithIndex:idx];
            [imageView.imageView sd_setImageWithURL:self.urlArray[idx] placeholderImage:[self getSelectedImg] options:SDWebImageRetryFailed progress:^(NSInteger receivedSize, NSInteger expectedSize, NSURL * _Nullable targetURL) {
                imageView.expectedSize = (CGFloat)expectedSize;
                imageView.receivedSize = (CGFloat)receivedSize;
            } completed:^(UIImage * _Nullable image, NSError * _Nullable error, SDImageCacheType cacheType, NSURL * _Nullable imageURL) {
                [imageView finishProcess];
            }];
            self.imageViewArray[idx] = imageView;
            
            if (self.imageViewArray.count > 1) {
                [self setIndexTitleWithImgView:imageView withIndex:idx];
            }
        }
    }];
}


- (void)addGesture{
    UITapGestureRecognizer *bgTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismiss)];
    bgTap.numberOfTapsRequired = 1;
    bgTap.numberOfTouchesRequired = 1;
    [_photoScrollView addGestureRecognizer:bgTap];
    
    UITapGestureRecognizer *zoomTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(zoom:)];
    zoomTap.numberOfTapsRequired = 2;
    zoomTap.numberOfTouchesRequired = 1;
    [_photoScrollView addGestureRecognizer:zoomTap];
    [bgTap requireGestureRecognizerToFail:zoomTap];
    
    UIPanGestureRecognizer *recognizer = [[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(move:)];
    [_photoScrollView addGestureRecognizer:recognizer];
    recognizer.delegate = self;
    _panStartY = _currentImageView.frame.origin.y;
    _panEndY = kHXSCREEN_HEIGHT;
}

- (BOOL)gestureRecognizerShouldBegin:(UIPanGestureRecognizer *)gestureRecognizer {
    
    CGPoint translation = [gestureRecognizer translationInView:gestureRecognizer.view];
    if (translation.y <= 0 || _isCanPan == NO) {
        return NO;
    }
    return YES;
}


- (void)move:(UIPanGestureRecognizer *)recognizer{
    if(_isCanPan == NO) return;
    
    CGPoint pt = [recognizer translationInView:_currentImageView];
    
    _currentImageView.imageView.frame = CGRectMake(_currentImageView.imageView.frame.origin.x + pt.x, _currentImageView.imageView.frame.origin.y + pt.y, _currentImageView.imageView.frame.size.width, _currentImageView.imageView.frame.size.height);
    
    _panMoveY += pt.y;
    
    [recognizer setTranslation:CGPointMake(0, 0) inView:_currentImageView.scrollView];
    
    if (recognizer.state == UIGestureRecognizerStateChanged){
        _effectView.alpha = 1 - _panMoveY / (_panEndY - _panStartY) * 1.5;
        if (pt.y > 0) {
            _currentImageView.imageView.transform = CGAffineTransformScale(_currentImageView.imageView.transform, kHXPhotoBrowserTransformShrink, kHXPhotoBrowserTransformShrink);
        } else if (pt.y < 0 && _currentImageView.scrollView.zoomScale < kHXPhotoBrowserZoomMin){
            _currentImageView.imageView.transform = CGAffineTransformScale(_currentImageView.imageView.transform, kHXPhotoBrowserTransformAmplify, kHXPhotoBrowserTransformAmplify);
        }
    } else if (recognizer.state == UIGestureRecognizerStateEnded){
        if (_currentImageView.imageView.frame.origin.y < kHXSCREEN_HEIGHT / 2 - _currentImageView.imageView.frame.size.height / 2 + kHXPhotoBrowserDisMissValue) {
            [UIView animateWithDuration:0.2 animations:^{
                self.currentImageView.imageView.frame = [self getNewRectWithIndex:self.currentIndex];
                self.effectView.alpha = 1;
            }];
            _panMoveY = 0;
        } else{
            [self dismiss];
        }
    }
}

- (void)zoom:(UITapGestureRecognizer *)recognizer{
    
    CGPoint touchPoint = [recognizer locationInView:self.view];
    
    if (_currentImageView.scrollView.zoomScale <= kHXPhotoBrowserZoomMin) {
        _currentImageView.scrollView.maximumZoomScale = kHXPhotoBrowserZoomMid;
        [_currentImageView.scrollView zoomToRect:CGRectMake(touchPoint.x, touchPoint.y, 1, 1) animated:YES];
        _isCanPan = NO;
    } else {
        [_currentImageView.scrollView setZoomScale:kHXPhotoBrowserZoomMin animated:YES];
        _isCanPan = YES;
    }
}



- (void)scrollViewWillBeginZooming:(UIScrollView *)scrollView withView:(UIView *)view{
    _isCanPan = NO;
}

- (void)scrollViewDidEndZooming:(UIScrollView *)scrollView withView:(UIView *)view atScale:(CGFloat)scale{
    if (scale <= kHXPhotoBrowserZoomMin || self.currentImageView.frame.size.height <= kHXSCREEN_HEIGHT) {
        [UIView animateWithDuration:0.3 animations:^{
            [self.currentImageView setCenter:CGPointMake(self.currentImageView.center.x,scrollView.center.y)];
        }];
    }
    
    if (scale <= kHXPhotoBrowserZoomMin) {
        _isCanPan = YES;
    }
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    NSInteger currentNum = scrollView.contentOffset.x / _pageWidth;
    
    if (_currentIndex != currentNum && ((NSInteger)scrollView.contentOffset.x % (NSInteger)_pageWidth == 0)) {
        [_currentImageView.scrollView setZoomScale:kHXPhotoBrowserZoomMin];
        _isCanPan = YES;
    }
    
    if (_isCanPan) {
        if (_imageViewArray) {
            _currentImageView = _imageViewArray[currentNum];
        }
        _currentIndex = currentNum;
    }
}

- (void)setParentVC:(UIViewController *)parentVC{
    _parentVC = parentVC;
    
    CATransition  *transition = [CATransition animation];
    transition.duration = 0.1f;
    transition.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    transition.type = kCATransitionFade;
    [parentVC.view.window.layer addAnimation:transition forKey:nil];
    
    [self setModalPresentationStyle:UIModalPresentationOverFullScreen];
    parentVC.view.backgroundColor = [UIColor clearColor];
    parentVC.modalPresentationStyle = UIModalPresentationOverFullScreen;
    parentVC.providesPresentationContextTransitionStyle = YES;
    parentVC.definesPresentationContext = YES;
}

- (void)setUrlStrArray:(NSArray<NSString *> *)urlStrArray{
    NSMutableArray *urlArray = [NSMutableArray array];
    
    for (NSString *str in urlStrArray) {
        [urlArray addObject:[NSURL URLWithString:str]];
    }
    
    self.photoCount = urlStrArray.count > 1 ? PhotoCountMultiple : PhotoCountSingle;
    self.pageWidth = self.photoCount ? kHXSCREEN_WIDTH + kHXPhotoBrowserPageMargin : kHXSCREEN_WIDTH;
    
    _urlArray = urlArray.copy;
}


- (void)show{
    [self setPhotoScrollView];
    
    [_parentVC presentViewController:self animated:NO completion:nil];
    
}

- (void)dismiss{
    if (_currentImageView.scrollView.zoomScale > kHXPhotoBrowserZoomMin) {
        [_currentImageView.scrollView setZoomScale:kHXPhotoBrowserZoomMin];
    }
    
    [UIView animateWithDuration:0.15 animations:^{
        self.currentImageView.imageView.frame = [self getStartRect];
        self.effectView.alpha = 0;
        
    } completion:^(BOOL finished) {
        [self.photoScrollView removeFromSuperview];
        self.photoScrollView = nil;
        [self dismissViewControllerAnimated:NO completion:nil];
    }];
}

- (void)setIndexTitleWithImgView:(HXPhotoImageView *)imgView withIndex:(NSInteger)index{
    imgView.indexTitle = [NSString stringWithFormat:@"%ld / %ld",index + 1,_imageViewArray.count];
}

- (void)transitionAnimation{
    [UIView animateWithDuration:0.25 animations:^{
        self.currentImageView.imageView.frame = [self getNewRectWithIndex:self.currentIndex];
    }];
}

- (void)setSelectedViewArray:(NSArray<UIView *> *)selectedViewArray{
    _selectedViewArray = selectedViewArray;
    
    NSMutableArray *arrayM = [NSMutableArray array];
    
    for (UIView *view in selectedViewArray) {
        UIImage *image = [UIImage new];
        
        if ([view isKindOfClass:[UIImageView class]]){
            UIImageView *img = (UIImageView *)view;
            image = img.image;
        }
        
        if ([view isKindOfClass:[UIButton class]]) {
            UIButton *btn = (UIButton *)view;
            image = btn.currentImage ? btn.currentImage : btn.currentBackgroundImage;
        }
        
        if (image) {
            CGSize size = [HXPhotoHelper uniformScaleWithImage:image withPhotoLevel:HXPhotoLevelWidth float:kHXSCREEN_WIDTH];
            [arrayM addObject:[NSNumber numberWithFloat:size.height]];
        } else{
            
        }
    }
    
    _heightArray = arrayM;
}

- (UIImage *)getSelectedImg{
    UIImage *image = [UIImage new];
    if ([_selectedViewArray[_currentIndex] isKindOfClass:[UIImageView class]]){
        UIImageView *img = (UIImageView *)_selectedViewArray[_currentIndex];
        image = img.image;
    }
    
    if ([_selectedViewArray[_currentIndex] isKindOfClass:[UIButton class]]) {
        UIButton *btn = (UIButton *)_selectedViewArray[_currentIndex];
        image = btn.currentImage ? btn.currentImage : btn.currentBackgroundImage;
    }
    
    return image;
}


- (CGRect)getStartRect{
    UIWindow * window=[[[UIApplication sharedApplication] delegate] window];
    CGRect startRact = [_selectedViewArray[_currentIndex] convertRect:_selectedViewArray[_currentIndex].bounds toView:window];
    
    return startRact;
}

- (CGRect)getNewRectWithIndex:(NSInteger)index{
    CGFloat width = kHXSCREEN_WIDTH;
    NSNumber *currentHeight = self.heightArray[index];
    CGFloat height = currentHeight.floatValue;
    CGRect newFrame = CGRectMake(0, kHXSCREEN_HEIGHT >= height ? (kHXSCREEN_HEIGHT - height) / 2 : 0, width, height);
    
    return newFrame;
}

@end
