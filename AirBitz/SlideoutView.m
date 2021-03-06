//
//  SlideoutView.m
//  AirBitz
//
//  Created by Tom on 3/25/15.
//  Copyright (c) 2015 AirBitz. All rights reserved.
//

#import "SlideoutView.h"
#import "PickerTextView.h"
#import "CoreBridge.h"
#import "ABC.h"
#import "User.h"
#import "LocalSettings.h"
#import "Util.h"
#import "CommonTypes.h"

@interface SlideoutView () <PickerTextViewDelegate >

{
    CGRect                      _originalSlideoutFrame;
    BOOL                        _open;
    NSString                    *_account;
    FadingAlertView             *_fadingAlert;
    UIButton                    *_blockingButton;
    UIView                      *_parentView;
}

@property (weak, nonatomic) IBOutlet UILabel                *conversionText;
@property (weak, nonatomic) IBOutlet UILabel                *accountText;
@property (weak, nonatomic) IBOutlet UIView                 *otherAccountsView;
@property (weak, nonatomic) IBOutlet UIView                 *lowerViews;
@property (weak, nonatomic) IBOutlet UIButton               *buySellButton;
@property (weak, nonatomic) IBOutlet UIButton               *logoutButton;
@property (weak, nonatomic) IBOutlet UIButton               *settingsButton;
@property (weak, nonatomic) IBOutlet UIView                 *buySellDivider;

@property (nonatomic, strong) NSArray                       *arrayAccounts;
@property (nonatomic, strong) NSArray                       *otherAccounts;
@property (nonatomic, weak) IBOutlet PickerTextView         *accountPicker;

@end

@implementation SlideoutView

+ (SlideoutView *)CreateWithDelegate:(id)del parentView:(UIView *)parentView withTab:(UIView *)tabBar;
{
    SlideoutView *v = [[[NSBundle mainBundle] loadNibNamed:@"SlideoutView~iphone" owner:self options:nil] objectAtIndex:0];
    v.delegate = del;

    v->_parentView = parentView;
    CGRect f = parentView.frame;
    int topOffset = HEADER_HEIGHT;
    int sliderWidth = 250;
    f.size.width = sliderWidth;
    f.origin.y = topOffset;
    f.origin.x = parentView.frame.size.width - f.size.width;
    f.size.height = parentView.frame.size.height - tabBar.frame.size.height - topOffset;
    v.frame = f;

    v->_originalSlideoutFrame = v.frame;

    f = v.frame;
    f.origin.x = f.origin.x + f.size.width;
    v.frame = f;
    v->_open = NO;

    tABC_Error error;
    bool isTestnet = false;
    ABC_IsTestNet(&isTestnet, &error);
    v->_buySellButton.hidden = isTestnet ? NO : YES;
    v->_buySellDivider.hidden = isTestnet ? NO : YES;
    
    UIColor *back = [UIColor colorWithRed:0.0 green:0.0 blue:1.0 alpha:0.05];
    [v->_logoutButton setBackgroundImage:[self imageWithColor:back] forState:UIControlStateHighlighted];
    [v->_settingsButton setBackgroundImage:[self imageWithColor:back] forState:UIControlStateHighlighted];
    [v->_buySellButton setBackgroundImage:[self imageWithColor:back] forState:UIControlStateHighlighted];
    return v;
}

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self) {
    }
    return self;
}

+ (UIImage *)imageWithColor:(UIColor *)color {
    CGRect rect = CGRectMake(0.0f, 0.0f, 1.0f, 1.0f);
    UIGraphicsBeginImageContext(rect.size);
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    CGContextSetFillColorWithColor(context, [color CGColor]);
    CGContextFillRect(context, rect);
    
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return image;
}

- (void)showSlideout:(BOOL)show
{
    self.accountPicker.delegate = self;
    
    // set up the specifics on our picker text view
    [self.accountPicker setTopMostView:self.otherAccountsView];
    CGRect frame = self.accountPicker.frame;
    frame.size.width = self.otherAccountsView.frame.size.width;
    self.accountPicker.frame = frame;
    self.accountPicker.pickerMaxChoicesVisible = 3;
    [self.accountPicker setAccessoryImage:[UIImage imageNamed:@"btn_close.png"]];
    
    tABC_AccountSettings *_pAccountSettings = NULL;
    tABC_Error Error;
    Error.code = ABC_CC_Ok;
    ABC_LoadAccountSettings([[User Singleton].name UTF8String],
                            [[User Singleton].password UTF8String],
                            &_pAccountSettings,
                            &Error);
    int num = _pAccountSettings->currencyNum;
    self.conversionText.text = [CoreBridge conversionStringFromNum:num withAbbrev:NO];
    
    
    self.accountText.text = [User Singleton].name;
    
    self.lowerViews.hidden = NO;
    self.otherAccountsView.hidden = YES;
    
    [self showSlideout:show withAnimation:YES];
}

- (void)showSlideout:(BOOL)show withAnimation:(BOOL)bAnimation
{
    if (!show)
    {
        CGRect frame = self.frame;
        frame.origin.x = frame.origin.x + frame.size.width;
        if (self.delegate && [self.delegate respondsToSelector:@selector(slideoutWillClose:)]) {
            [self.delegate slideoutWillClose:self];
        }
        if (bAnimation) {
            [UIView animateWithDuration:0.35
                                delay:0.0
                                options:UIViewAnimationOptionCurveEaseOut
                            animations:^
            {
                self.frame = frame;
            }
                            completion:^(BOOL finished)
            {
                
            }];
            [UIView animateWithDuration:0.35
                                  delay:0.0
                                options:UIViewAnimationOptionCurveEaseOut
                             animations:^
             {
                 _blockingButton.alpha = 0;
             }
                             completion:^(BOOL finished)
             {
                 [self removeBlockingButton:self->_parentView];
             }];
        } else {
            self.frame = frame;
            [self removeBlockingButton:self->_parentView];
        }
    } else {
        if (self.delegate && [self.delegate respondsToSelector:@selector(slideoutWillOpen:)]) {
            [self.delegate slideoutWillOpen:self];
        }
        if (bAnimation) {
            [UIView animateWithDuration:0.35
                                delay:0.0
                                options:UIViewAnimationOptionCurveEaseOut
                            animations:^
            {
                self.frame = _originalSlideoutFrame;
            }
                            completion:^(BOOL finished)
            {
                
            }];
            [self addBlockingButton:self->_parentView];
            [UIView animateWithDuration:0.35
                                  delay:0.0
                                options:UIViewAnimationOptionCurveEaseOut
                             animations:^
             {
                 _blockingButton.alpha = 0.5;
             }
                             completion:^(BOOL finished)
             {
                 
             }];
        } else {
            self.frame = _originalSlideoutFrame;
        }
    }
    _open = show;
}

- (IBAction)buysellTouched
{
    if (self.delegate && [self.delegate respondsToSelector:@selector(slideoutBuySell)]) {
        [self.delegate slideoutBuySell];
    }
}

- (IBAction)accountTouched
{
    if(self.otherAccountsView.hidden) {
        [self updateOtherAccounts:self.accountText.text];
        if(self.otherAccounts.count > 0)
        {
            [self.accountPicker updateChoices:self.otherAccounts] ;
            self.otherAccountsView.hidden = NO;
            self.lowerViews.hidden = YES;
        }
    }
    else
    {
        self.otherAccountsView.hidden = YES;
        self.lowerViews.hidden = NO;
    }
    if (self.delegate && [self.delegate respondsToSelector:@selector(slideoutAccount)]) {
        [self.delegate slideoutAccount];
    }
}

- (IBAction)settingTouched
{
    if (self.delegate && [self.delegate respondsToSelector:@selector(slideoutSettings)]) {
        [self.delegate slideoutSettings];
    }
}

- (IBAction)logoutTouched
{
    if (self.delegate && [self.delegate respondsToSelector:@selector(slideoutLogout)]) {
        [self.delegate slideoutLogout];
    }
    [self removeBlockingButton:self->_parentView];
}

- (BOOL)isOpen
{
    return _open;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    CGPoint translation = [(UIPanGestureRecognizer *)gestureRecognizer translationInView:gestureRecognizer.view.superview];
    return fabsf(translation.x) > fabsf(translation.y);
}

- (void)handleRecognizer:(UIPanGestureRecognizer *)recognizer fromBlock:(bool) block
{
    if(![self gestureRecognizerShouldBegin:recognizer])
    {
        return;
    }
    CGPoint translation = [recognizer translationInView:self->_parentView];
    CGPoint location = [recognizer locationInView:self->_parentView];
    int openLeftX = self->_parentView.bounds.size.width - self.bounds.size.width;
    bool halfwayOut = location.x < self->_parentView.bounds.size.width - self.bounds.size.width / 2;
    NSLog(@"transX, locX, centerX: %f %f %f", translation.x, location.x, self.center.x);
    
    if(recognizer.state == UIGestureRecognizerStateEnded)
    {
        [self showSlideout:halfwayOut];
        return;
    }
    else if(recognizer.state == UIGestureRecognizerStateBegan)
    {
        [self addBlockingButton:self->_parentView];
    }
    
    if(block)
    {
        //over slideout
        if(location.x >= openLeftX) {
            self.center = CGPointMake(location.x + self.bounds.size.width / 2, self.center.y);
        }
    }
    else
    {
        if(-translation.x > self.bounds.size.width) {
            self.center = CGPointMake(self->_parentView.bounds.size.width - self.bounds.size.width/2, self.center.y);
        }
        else
        {
            self.center = CGPointMake(self->_parentView.bounds.size.width + translation.x + self.bounds.size.width/2, self.center.y);
        }
    }
    
    [self updateBlockingButtonAlpha:self.frame.origin.x];
}

- (void)updateBlockingButtonAlpha:(int) frameOriginX
{
    float alpha = (self->_parentView.bounds.size.width - frameOriginX) / self->_parentView.bounds.size.width;
    if(alpha > 0.5)
    {
        alpha = 0.5;
    }
    _blockingButton.alpha = alpha;
}

- (void)addBlockingButton:(UIView *)view
{
    if(!_blockingButton)
    {
        _blockingButton = [UIButton buttonWithType:UIButtonTypeCustom];
        CGRect frame = view.bounds;
        _blockingButton.frame = frame;
        _blockingButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.0 blue:0.0 alpha:0.5];
        [self->_parentView insertSubview:_blockingButton belowSubview:self];
        _blockingButton.alpha = 0.0;
    
        [_blockingButton addTarget:self
                        action:@selector(blockingButtonHit:)
              forControlEvents:UIControlEventTouchUpInside];
        [self installPanningDetection];
    }
}

- (void)removeBlockingButton:(UIView *)view
{
    [_blockingButton removeFromSuperview];
    _blockingButton = nil;
}

- (void)blockingButtonHit:(UIButton *)button
{
    [self showSlideout:NO];
}

- (void)installPanningDetection
{
    UIPanGestureRecognizer *gesturePanOnBlocker = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleBlockingButtonPan:)];
    [self->_blockingButton addGestureRecognizer:gesturePanOnBlocker];
    UIPanGestureRecognizer *gesturePanOnSlideout = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleBlockingButtonPan:)];
    [self addGestureRecognizer:gesturePanOnSlideout];
}

// used by the guesture recognizer to ignore exit
- (BOOL)haveSubViewsShowing
{
    return NO;
}

- (void)handleBlockingButtonPan:(UIPanGestureRecognizer *) recognizer {
    [self handleRecognizer:recognizer fromBlock:YES];
}


#pragma mark - PickerTextView delegates

- (void)pickerTextViewPopupSelected:(PickerTextView *)pickerTextView onRow:(NSInteger)row
{
    [self.accountPicker dismissPopupPicker];
    
    // set the text field to the choice
    NSString *account = [self.otherAccounts objectAtIndex:row];
    [LocalSettings controller].cachedUsername = account;
    if (self.delegate && [self.delegate respondsToSelector:@selector(slideoutLogout)]) {
        [self.delegate slideoutLogout];
    }
}

- (void)removeAccount:(NSString *)account
{
    tABC_Error error;
    tABC_CC cc = ABC_AccountDelete((const char*)[account UTF8String], &error);
    if(cc == ABC_CC_Ok) {
        [self getAllAccounts];
        [self.accountPicker updateChoices:self.arrayAccounts];
    }
    else {
        [self showFadingError:[Util errorMap:&error]];
    }
}

- (void)getAllAccounts
{
    char * pszUserNames;
    tABC_Error error;
    __block tABC_CC result = ABC_ListAccounts(&pszUserNames, &error);
    switch (result)
    {
        case ABC_CC_Ok:
        {
            NSString *str = [NSString stringWithCString:pszUserNames encoding:NSUTF8StringEncoding];
            NSArray *arrayAccounts = [str componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
            NSMutableArray *stringArray = [[NSMutableArray alloc] init];
            for(NSString *str in arrayAccounts)
            {
                if(str && str.length!=0)
                {
                    [stringArray addObject:str];
                }
            }
            self.arrayAccounts = [stringArray copy];
            break;
        }
        default:
        {
            tABC_Error temp;
            temp.code = result;
            [self showFadingError:[Util errorMap:&temp]];
            break;
        }
    }
}

- (void)updateOtherAccounts:(NSString *)username
{
    [self getAllAccounts];
    NSMutableArray *stringArray = [[NSMutableArray alloc] init];
    for(NSString *str in self.arrayAccounts)
    {
        if(![str isEqualToString:username])
        {
            [stringArray addObject:str];
        }
    }
    self.otherAccounts = [stringArray copy];
}


- (void)pickerTextViewDidTouchAccessory:(PickerTextView *)pickerTextView categoryString:(NSString *)string
{
    _account = string;
    NSString *message = [NSString stringWithFormat:@"Delete %@ on this device only?",
                         string];
    UIAlertView *alert = [[UIAlertView alloc]
                          initWithTitle:NSLocalizedString(@"Delete Account", nil)
                          message:NSLocalizedString(message, nil)
                          delegate:self
                          cancelButtonTitle:@"No"
                          otherButtonTitles:@"Yes", nil];
    [alert show];
    [self.accountPicker dismissPopupPicker];
}

- (void)pickerTextViewFieldDidShowPopup:(PickerTextView *)pickerTextView
{
    CGRect popupWindowFrame = pickerTextView.popupPicker.frame;
    
    popupWindowFrame.size.width = pickerTextView.frame.size.width;
    pickerTextView.popupPicker.frame = popupWindowFrame;
}

- (void)showFadingError:(NSString *)message
{
//    _fadingAlert = [FadingAlertView CreateInsideView:self.view withDelegate:self];
//    _fadingAlert.message = message;
//    _fadingAlert.fadeDuration = 2;
//    _fadingAlert.fadeDelay = 5;
//    [_fadingAlert blockModal:NO];
//    [_fadingAlert showSpinner:NO];
//    [_fadingAlert showFading];
}

#pragma mark - UIAlertView Delegate

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex
{
    // if they said they wanted to delete the account
    if (buttonIndex == 1)
    {
        [self removeAccount:_account];
        [self accountTouched];
    }
}

@end
