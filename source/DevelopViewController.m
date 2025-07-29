#import "DevelopViewController.h"
#import "RawDecoder.h"
#import <UIKit/UIKit.h>

@interface DevelopViewController () <UIScrollViewDelegate>
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIButton *zoomInButton;
@property (nonatomic, strong) UIButton *zoomOutButton;
@end

@implementation DevelopViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    // Spinner
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.spinner.color = [UIColor systemYellowColor]; // 🌟 Make it pop against dark background
    self.spinner.center = self.view.center;
    self.spinner.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin |
                                    UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    [self.view addSubview:self.spinner];
    [self.spinner startAnimating];

    // Scroll view setup
    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.delegate = self;
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.scrollView.minimumZoomScale = 0.1;
    self.scrollView.maximumZoomScale = 8.0;
    self.scrollView.bouncesZoom = YES;
    self.scrollView.alwaysBounceVertical = YES;
    self.scrollView.alwaysBounceHorizontal = YES;
    [self.view addSubview:self.scrollView];
    
    // ☀️ Exposure Tool Button
    UIButton *exposureButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [exposureButton setTitle:@"☀️" forState:UIControlStateNormal];
    exposureButton.titleLabel.font = [UIFont systemFontOfSize:24];
    exposureButton.backgroundColor = [UIColor clearColor];
    exposureButton.translatesAutoresizingMaskIntoConstraints = NO;
    [exposureButton addTarget:self action:@selector(exposureButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:exposureButton];

    // Constraints: top-right corner
    [NSLayoutConstraint activateConstraints:@[
        [exposureButton.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12],
        [exposureButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12],
        [exposureButton.widthAnchor constraintEqualToConstant:44],
        [exposureButton.heightAnchor constraintEqualToConstant:44],
    ]];
    
    // Load image asynchronously
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        UIImage *image = [RawDecoder decodeRAWAtPath:self.fileURL.path];

        dispatch_async(dispatch_get_main_queue(), ^{
            [self.spinner stopAnimating];
            [self.spinner removeFromSuperview];

            if (image) {
                self.imageView = [[UIImageView alloc] initWithImage:image];
                self.imageView.contentMode = UIViewContentModeScaleAspectFit;
                self.imageView.userInteractionEnabled = YES;

                CGSize imageSize = image.size;
                self.imageView.frame = CGRectMake(0, 0, imageSize.width, imageSize.height);
                self.scrollView.contentSize = imageSize;
                [self.scrollView addSubview:self.imageView];

                // Fit image to screen
                [self fitImageInScrollView];
                [self centerImageInScrollView];

                [self addZoomButtons];
            } else {
                UILabel *label = [[UILabel alloc] initWithFrame:self.view.bounds];
                label.text = @"❌ Failed to decode RAW image.";
                label.textColor = [UIColor whiteColor];
                label.textAlignment = NSTextAlignmentCenter;
                label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                [self.view addSubview:label];
            }
        });
    });
}

- (void)exposureButtonTapped {
    NSLog(@"☀️ Exposure tool tapped (placeholder)");
}

- (void)addZoomButtons {
    CGFloat padding = 16;
    CGFloat buttonSize = 44;

    self.zoomInButton = [self createButtonWithTitle:@"＋" action:@selector(zoomIn)];
    self.zoomOutButton = [self createButtonWithTitle:@"－" action:@selector(zoomOut)];

    self.zoomInButton.frame = CGRectMake(self.view.bounds.size.width - buttonSize - padding,
                                         self.view.bounds.size.height - 2 * (buttonSize + padding),
                                         buttonSize, buttonSize);

    self.zoomOutButton.frame = CGRectMake(self.view.bounds.size.width - buttonSize - padding,
                                          self.view.bounds.size.height - (buttonSize + padding),
                                          buttonSize, buttonSize);

    self.zoomInButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin;
    self.zoomOutButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin;

    [self.view addSubview:self.zoomInButton];
    [self.view addSubview:self.zoomOutButton];
}

- (UIButton *)createButtonWithTitle:(NSString *)title action:(SEL)selector {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    button.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    button.layer.cornerRadius = 8;
    [button addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)zoomIn {
    CGFloat newZoom = MIN(self.scrollView.zoomScale * 1.5, self.scrollView.maximumZoomScale);
    [self.scrollView setZoomScale:newZoom animated:YES];
}

- (void)zoomOut {
    CGFloat newZoom = MAX(self.scrollView.zoomScale / 1.5, self.scrollView.minimumZoomScale);
    [self.scrollView setZoomScale:newZoom animated:YES];
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return self.imageView;
}

- (void)centerImageInScrollView {
    CGSize boundsSize = self.scrollView.bounds.size;
    CGRect frameToCenter = self.imageView.frame;

    if (frameToCenter.size.width < boundsSize.width) {
        frameToCenter.origin.x = (boundsSize.width - frameToCenter.size.width) / 2.0;
    } else {
        frameToCenter.origin.x = 0;
    }

    if (frameToCenter.size.height < boundsSize.height) {
        frameToCenter.origin.y = (boundsSize.height - frameToCenter.size.height) / 2.0;
    } else {
        frameToCenter.origin.y = 0;
    }

    self.imageView.frame = frameToCenter;
}

- (void)fitImageInScrollView {
    if (!self.imageView || !self.imageView.image) return;

    CGSize imageSize = self.imageView.image.size;
    CGSize scrollSize = self.scrollView.bounds.size;

    CGFloat scaleWidth = scrollSize.width / imageSize.width;
    CGFloat scaleHeight = scrollSize.height / imageSize.height;
    CGFloat minScale = MIN(scaleWidth, scaleHeight);

    self.scrollView.minimumZoomScale = minScale;
    [self.scrollView setZoomScale:minScale animated:NO];
}

@end
