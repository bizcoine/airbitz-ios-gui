//
//  TransactionDetailsViewController.m
//  AirBitz
//
//  Created by Carson Whitsett on 3/3/14.
//  Copyright (c) 2014 AirBitz. All rights reserved.
//

#import <AddressBook/AddressBook.h>
#import "TransactionDetailsViewController.h"
#import "TxOutput.h"
#import "CoreBridge.h"
#import "User.h"
#import "NSDate+Helper.h"
#import "ABC.h"
#import "InfoView.h"
#import "CalculatorView.h"
#import "PickerTextView.h"
#import "StylizedTextField.h"
#import "DL_URLServer.h"
#import "Server.h"
#import "Location.h"
#import "CJSONDeserializer.h"
#import "Util.h"
#import "CommonTypes.h"
#import "PayeeCell.h"
#import "BusinessDetailsViewController.h"
#import "Location.h"
#import "CommonTypes.h"
#import "PopupPickerView.h"
#import <QuartzCore/QuartzCore.h>

#define ARRAY_CATEGORY_PREFIXES         @[@"Expense:",@"Income:",@"Transfer:",@"Exchange:"]
#define ARRAY_CATEGORY_PREFIXES_NOCOLON @[@"Expense",@"Income",@"Transfer",@"Exchange"]
#define ARRAY_CATEGORY_PREFIX_EXPENSE    0
#define ARRAY_CATEGORY_PREFIX_INCOME     1
#define ARRAY_CATEGORY_PREFIX_TRANSFER   2
#define ARRAY_CATEGORY_PREFIX_EXCHANGE   3

#define PICKER_WIDTH                    160
#define PICKER_CELL_HEIGHT              40

#define PICKER_MAX_CELLS_VISIBLE 4

#define USE_AUTOCOMPLETE_QUERY 0

#define TEXTFIELD_VERTICAL_SPACE_OFFSET    7.0 /* how much space between screen header and textField when textField is scrolled all the way to the top */

#define SEARCH_RADIUS        16093
#define CACHE_AGE_SECS       (60 * 15) // 15 min
#define CACHE_IMAGE_AGE_SECS (60 * 60) // 60 hour

#define TABLE_CELL_BACKGROUND_COLOR [UIColor colorWithRed:213.0/255.0 green:237.0/255.0 blue:249.0/255.0 alpha:1.0]

#define PHOTO_BORDER_WIDTH          2.0f
#define PHOTO_BORDER_COLOR          [UIColor lightGrayColor]
#define PHOTO_BORDER_CORNER_RADIUS  5.0

#define MIN_AUTOCOMPLETE    3 // if there are less than this in the autocomplete, then include all businesses

typedef enum eRequestType
{
    RequestType_BusinessesNear,
    RequestType_BusinessesAuto,
    RequestType_BusinessDetails
} tRequestType;

@interface TransactionDetailsViewController () <UITextFieldDelegate, UITextViewDelegate, InfoViewDelegate, CalculatorViewDelegate,
                                                DL_URLRequestDelegate, UITableViewDataSource, UITableViewDelegate, PickerTextViewDelegate,PopupPickerViewDelegate,
                                                UIGestureRecognizerDelegate, UIAlertViewDelegate,
                                                LocationDelegate, BusinessDetailsViewControllerDelegate>
{
    UITextField     *_activeTextField;
    UITextView      *_activeTextView;
    CGRect          _originalFrame;
    CGRect          _originalHeaderFrame;
    CGRect          _originalContentFrame;
    CGRect          _originalScrollableContentFrame;
    UITableView     *_autoCompleteTable; //table of autoComplete search results (including address book entries)
    BOOL            _bDoneSentToDelegate;
    unsigned int    _bizId;
    UIAlertView     *_recoveryAlert;
    BusinessDetailsViewController *businessDetailsController;
}

@property (nonatomic, weak) IBOutlet UIView                 *headerView;
@property (nonatomic, weak) IBOutlet UIView                 *contentView;
@property (nonatomic, weak) IBOutlet UIView                 *scrollableContentView;

@property (weak, nonatomic) IBOutlet UIView                 *viewPhoto;
@property (weak, nonatomic) IBOutlet UIButton               *imagePhotoButton;
@property (weak, nonatomic) IBOutlet UIImageView            *imagePhoto;
@property (nonatomic, weak) IBOutlet UILabel                *dateLabel;
@property (weak, nonatomic) IBOutlet UIImageView            *imageNameEmboss;
@property (nonatomic, weak) IBOutlet StylizedTextField      *nameTextField;
@property (nonatomic, weak) IBOutlet UIButton               *advancedDetailsButton;
@property (weak, nonatomic) IBOutlet UIImageView            *imageAmountEmboss;
@property (nonatomic, weak) IBOutlet UILabel                *walletLabel;
@property (nonatomic, weak) IBOutlet UILabel                *bitCoinLabel;
@property (weak, nonatomic) IBOutlet UILabel                *labelBTC;
@property (weak, nonatomic) IBOutlet UILabel                *labelFee;
//@property (weak, nonatomic) IBOutlet UILabel                *labelFiatSign;
@property (weak, nonatomic) IBOutlet UILabel                *labelFiatName;
@property (weak, nonatomic) IBOutlet UIImageView            *imageFiatEmboss;
@property (nonatomic, weak) IBOutlet UITextField            *fiatTextField;
@property (weak, nonatomic) IBOutlet UIImageView            *imageBottomEmboss;
@property (weak, nonatomic) IBOutlet UILabel                *labelCategory;
@property (weak, nonatomic) IBOutlet UIImageView            *imageCategoryEmboss;
@property (weak, nonatomic) IBOutlet PickerTextView         *pickerTextCategory;
@property (weak, nonatomic) IBOutlet UILabel                *labelNotes;
@property (weak, nonatomic) IBOutlet UIImageView            *imageNotesEmboss;
@property (nonatomic, weak) IBOutlet UITextView             *notesTextView;
@property (nonatomic, weak) IBOutlet UIButton               *doneButton;
@property (nonatomic, weak) IBOutlet UIButton               *categoryButton;
@property (nonatomic, strong)        PopupPickerView        *categoryPopupPicker;
@property (nonatomic, strong)        UIButton               *buttonBlocker;



@property (nonatomic, weak) IBOutlet CalculatorView         *keypadView;
@property (weak, nonatomic) IBOutlet UIButton               *buttonBack;

@property (nonatomic, strong)        NSArray                *arrayCategories;
@property (nonatomic, strong)        NSArray                *arrayContacts;
@property (nonatomic, strong)        NSMutableArray         *arrayNearBusinesses; // businesses that match distance criteria
@property (nonatomic, strong)        NSMutableArray         *arrayOtherBusinesses;    // businesses found using auto complete
@property (nonatomic, strong)        NSArray                *arrayAutoComplete; // array displayed in the drop-down table when user is entering a name
@property (nonatomic, strong)        NSMutableDictionary    *dictImages; // images for the contacts and businesses
@property (nonatomic, strong)        NSMutableDictionary    *dictAddresses; // addresses for the contacts and businesses
@property (nonatomic, strong)        NSMutableDictionary    *dictThumbnailURLs; // urls for business thumbnails
@property (nonatomic, strong)        NSMutableDictionary    *dictBizIds; // bizIds for the businesses
@property (nonatomic, strong)        NSMutableArray         *arrayThumbnailsToRetrieve; // array of names of businesses for which images need to be retrieved
@property (nonatomic, strong)        NSMutableArray         *arrayThumbnailsRetrieving; // array of names of businesses for which images are currently being retrieved
@property (nonatomic, strong)        NSMutableArray         *arrayAutoCompleteQueries; // array of names for which autocomplete queries have been made

@end

@implementation TransactionDetailsViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    // initialize arrays
    self.arrayNearBusinesses = [[NSMutableArray alloc] init];
    self.arrayOtherBusinesses = [[NSMutableArray alloc] init];
    self.arrayAutoComplete = @[];
    self.dictImages = [[NSMutableDictionary alloc] init];
    self.dictAddresses = [[NSMutableDictionary alloc] init];
    self.dictThumbnailURLs = [[NSMutableDictionary alloc] init];
    self.dictBizIds = [[NSMutableDictionary alloc] init];
    self.arrayThumbnailsToRetrieve = [[NSMutableArray alloc] init];
    self.arrayThumbnailsRetrieving = [[NSMutableArray alloc] init];
    self.arrayAutoCompleteQueries = [[NSMutableArray alloc] init];

    // if there is a photo, then add it as the first photo in our images
    if (self.photo)
    {
        [self.dictImages setObject:self.photo forKey:self.transaction.strName];
    }

    // if there is a biz id, add this biz as the first bizid
    if (self.transaction.bizId)
    {
        [self.dictBizIds setObject:[NSNumber numberWithInt:self.transaction.bizId] forKey:self.transaction.strName];
    }

    // resize ourselves to fit in area
    [Util resizeView:self.view withDisplayView:self.contentView];
    [self updateDisplayLayout];

    _bDoneSentToDelegate = NO;

    self.buttonBack.hidden = !self.bOldTransaction;
    if (_wallet)
    {
        _labelFiatName.text = _wallet.currencyAbbrev;
    }

    // set up our user blocking button
    self.buttonBlocker = [UIButton buttonWithType:UIButtonTypeCustom];
    self.buttonBlocker.backgroundColor = [UIColor clearColor];
    [self.buttonBlocker addTarget:self action:@selector(buttonBlockerTouched:) forControlEvents:UIControlEventTouchUpInside];
    self.buttonBlocker.frame = self.view.bounds;
    self.buttonBlocker.hidden = YES;
    [self.scrollableContentView addSubview:self.buttonBlocker];
    
    // get the list of businesses
    [self generateListOfNearBusinesses];

    // update our array of categories
    [self loadCategories];

    // set the keyboard return button based upon mode
    self.nameTextField.returnKeyType = (self.bOldTransaction ? UIReturnKeyDone : UIReturnKeyNext);
    self.pickerTextCategory.textField.returnKeyType = UIReturnKeyDone;
    self.notesTextView.returnKeyType = UIReturnKeyDone;

    // load all the names from the address book
    [self generateListOfContactNames];

    self.keypadView.delegate = self;
    self.keypadView.textField = self.fiatTextField;
    
    self.fiatTextField.delegate = self;
#ifdef __IPHONE_8_0
    [self.keypadView removeFromSuperview];
#endif
    self.fiatTextField.inputView = self.keypadView;
    self.notesTextView.delegate = self;
    self.nameTextField.delegate = self;

    // get a callback when there are changes
    [self.nameTextField addTarget:self action:@selector(textFieldDidChange:) forControlEvents:UIControlEventEditingChanged];

    // set up the specifics on our picker text view
    self.pickerTextCategory.textField.borderStyle = UITextBorderStyleNone;
    self.pickerTextCategory.textField.backgroundColor = [UIColor clearColor];
    self.pickerTextCategory.textField.font = [UIFont systemFontOfSize:14];
    self.pickerTextCategory.textField.clearButtonMode = UITextFieldViewModeNever;
    self.pickerTextCategory.textField.autocapitalizationType = UITextAutocapitalizationTypeWords;
    self.pickerTextCategory.textField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.pickerTextCategory.textField.spellCheckingType = UITextSpellCheckingTypeNo;
    self.pickerTextCategory.textField.textColor = [UIColor whiteColor];
    self.pickerTextCategory.textField.tintColor = [UIColor whiteColor];
    [self.pickerTextCategory setTopMostView:self.view];
    [self.pickerTextCategory setCategories:self.arrayCategories];
    //self.pickerTextCategory.pickerMaxChoicesVisible = PICKER_MAX_CELLS_VISIBLE;
    self.pickerTextCategory.cropPointBottom = 360; // magic number
    self.pickerTextCategory.delegate = self;

    _bizId = self.transaction.bizId;

    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateStyle:NSDateFormatterMediumStyle];
    [dateFormatter setTimeStyle:NSDateFormatterMediumStyle];
    self.dateLabel.text = [dateFormatter stringFromDate:self.transaction.date];
    self.nameTextField.text = self.transaction.strName;
    self.notesTextView.text = self.transaction.strNotes;
    self.pickerTextCategory.textField.text = self.transaction.strCategory;

    NSString *strPrefix;
    strPrefix = [self categoryPrefix:self.pickerTextCategory.textField.text];
    self.pickerTextCategory.textField.text = [self categoryPrefixRemove:self.pickerTextCategory.textField.text];
    
    [self setCategoryButtonText:strPrefix];

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [center addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];

    self.nameTextField.placeholder = NSLocalizedString(@"Enter Payee", nil);
    self.nameTextField.autocapitalizationType = UITextAutocapitalizationTypeWords;
    self.nameTextField.font = [UIFont systemFontOfSize:18];
    
    [Util stylizeTextField:self.pickerTextCategory.textField];
    [Util stylizeTextView:self.notesTextView];
    
    _originalHeaderFrame = self.headerView.frame;
    _originalContentFrame = self.contentView.frame;
    _originalScrollableContentFrame = self.scrollableContentView.frame;

    // set up the photo view
    self.viewPhoto.layer.shadowColor = [UIColor blackColor].CGColor;
    self.viewPhoto.layer.shadowOpacity = 0.5;
    self.viewPhoto.layer.shadowRadius = 10;
    self.viewPhoto.layer.shadowOffset = CGSizeMake(5.0f, 5.0f);
    
    [self updatePhoto];
    
    // add left to right swipe detection for going back
    [self installLeftToRightSwipeDetection];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(tabBarButtonReselect:) name:NOTIFICATION_TAB_BAR_BUTTON_RESELECT object:nil];
    
    [Location initAllWithDelegate: self];
}

- (void)viewDidUnload
{
    [Location freeAll];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear: animated];

    if (_originalFrame.size.height == 0)
    {
        CGRect frame = self.view.frame;
        frame.origin.x = 0;
        frame.origin.y = 0;
        _originalFrame = frame;
        
        if (_transactionDetailsMode == TD_MODE_SENT)
        {
            self.walletLabel.text = [NSString stringWithFormat:@"From: %@", self.transaction.strWalletName];
        }
        else
        {
            self.walletLabel.text = [NSString stringWithFormat:@"To: %@", self.transaction.strWalletName];
        }
        
        if (self.transaction.amountFiat == 0)
        {
            double currency;
            tABC_Error error;
            ABC_SatoshiToCurrency([[User Singleton].name UTF8String],
                                  [[User Singleton].password UTF8String], 
                                  self.transaction.amountSatoshi, &currency, _wallet.currencyNum, &error);
            self.fiatTextField.text = [NSString stringWithFormat:@"%.2f", currency];
        }
        else
        {
            self.fiatTextField.text = [NSString stringWithFormat:@"%.2f", self.transaction.amountFiat];
        }

        // push the calculator keypad to below the bottom of the screen
        frame = self.keypadView.frame;
        frame.origin.y = frame.origin.y + frame.size.height;
        self.keypadView.frame = frame;
    }

    NSMutableString *coinFormatted = [[NSMutableString alloc] init];
    NSMutableString *feeFormatted = [[NSMutableString alloc] init];

    if (self.transaction.amountSatoshi < 0)
    {
        [coinFormatted appendString:
            [CoreBridge formatSatoshi:self.transaction.amountSatoshi + (self.transaction.minerFees + self.transaction.abFees) withSymbol:false]];

        [feeFormatted appendFormat:@"+%@ fee",
         [CoreBridge formatSatoshi:self.transaction.minerFees + self.transaction.abFees withSymbol:false]];
    }
    else
    {
        [coinFormatted appendString:
            [CoreBridge formatSatoshi:self.transaction.amountSatoshi withSymbol:false]];
    }
    self.labelFee.text = feeFormatted;
    self.bitCoinLabel.text = coinFormatted;
    self.labelBTC.text = [User Singleton].denominationLabel;
    
    
    if (self.categoryButton.titleLabel.text == nil)
    {
        if (_transactionDetailsMode == TD_MODE_SENT)
        {
            [self setCategoryButtonText:@"Expense"];
        }
        else if (_transactionDetailsMode == TD_MODE_RECEIVED)
        {
            [self setCategoryButtonText:@"Income"];
        }
    }

    [Location startLocatingWithPeriod: LOCATION_UPDATE_PERIOD];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [Location stopLocating];
    [self dismissBusinessDetails];
}

- (void)viewDidDisappear:(BOOL)animated
{
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [DL_URLServer.controller cancelAllRequestsForDelegate:self];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


#pragma mark - Action Methods

- (IBAction)CategoryButton
{
    NSArray *arrayCategories = ARRAY_CATEGORY_PREFIXES_NOCOLON;

    [self scrollContentViewBackToOriginalPosition];
    
    self.categoryPopupPicker = [PopupPickerView CreateForView:self.scrollableContentView
                                               relativeToView:self.categoryButton
                                             relativePosition:PopupPickerPosition_Right
                                                  withStrings:arrayCategories
                                               fromCategories:nil
                                                  selectedRow:-1
                                                    withWidth:PICKER_WIDTH
                                                withAccessory:nil
                                                andCellHeight:PICKER_CELL_HEIGHT
                                ];
    self.categoryPopupPicker.userData = nil;
    //prevent popup from extending behind tool bar
    [self.categoryPopupPicker addCropLine:CGPointMake(0, self.view.window.frame.size.height - TOOLBAR_HEIGHT) direction:PopupPickerPosition_Below animated:NO];
    self.categoryPopupPicker.delegate = self;
    [self blockUser:TRUE];
    
}

- (IBAction)setCategoryButtonText:(NSString *)text
{
    if ([text isEqual:@"Income"])
    {
        [self.categoryButton setBackgroundColor:[UIColor colorWithRed:0.3
                                                                green:0.6
                                                                 blue:0.0
                                                                alpha:1.0]];
    }
    else if ([text isEqual:@"Expense"])
    {
        [self.categoryButton setBackgroundColor:[UIColor colorWithRed:0.7
                                                                green:0.0
                                                                 blue:0.0
                                                                alpha:1.0]];
    }
    else if ([text isEqual:@"Transfer"])
    {
        [self.categoryButton setBackgroundColor:[UIColor colorWithRed:0.0
                                                                green:0.4
                                                                 blue:0.8
                                                                alpha:1.0]];
    }
    else
    {
        [self.categoryButton setBackgroundColor:[UIColor colorWithRed:0.8
                                                                green:0.4
                                                                 blue:0.0
                                                                alpha:1.0]];
    }
    
    [self.categoryButton setTitle:text forState:UIControlStateNormal];
}


- (IBAction)Done
{
    [DL_URLServer.controller cancelAllRequestsForDelegate:self];

    [self resignAllResponders];

    NSMutableString *strFullCategory = [[NSMutableString alloc] init];
    [strFullCategory appendString:self.categoryButton.titleLabel.text];
    [strFullCategory appendString:@":"];
    [strFullCategory appendString:self.pickerTextCategory.textField.text];
        
    // add the category if we didn't have it
    [self addCategory: strFullCategory];
    self.transaction.strCategory = strFullCategory;
    self.transaction.strName = [self.nameTextField text];
    self.transaction.strNotes = [self.notesTextView text];
    
    double amountFiat = [[self.fiatTextField text] doubleValue];

    if (_transactionDetailsMode == TD_MODE_SENT)
    {
        if (amountFiat > 0)
        {
            // Make amount negative since calculator cant work with negative values
            amountFiat *= -1;
        }
    }
    self.transaction.amountFiat = amountFiat;
    self.transaction.bizId = _bizId;

    [CoreBridge storeTransaction: self.transaction];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^ {
        if (_wallet && !_bOldTransaction && [CoreBridge needsRecoveryQuestionsReminder:_wallet]) {
            _recoveryAlert = [[UIAlertView alloc]
                                initWithTitle:NSLocalizedString(@"Recovery Password Reminder", nil)
                                message:NSLocalizedString(@"You've received Bitcoin! We STRONGLY recommend setting up Password Recovery questions and answers. Otherwise you will NOT be able to access your account if your password is forgotten.", nil)
                                delegate:self
                                cancelButtonTitle:NSLocalizedString(@"Cancel", nil)
                                otherButtonTitles:NSLocalizedString(@"OK", nil), nil];
            dispatch_async(dispatch_get_main_queue(), ^ {
                [_recoveryAlert show];
            });
        } else {
            dispatch_async(dispatch_get_main_queue(), ^ {
                [self exit:YES];
            });
        }
    });
}

- (IBAction)PopupPickerViewSelected:(PopupPickerView *)view onRow:(NSInteger)row userData:(id)data
{
    NSString *strPrefix;
    
    NSArray *array = ARRAY_CATEGORY_PREFIXES_NOCOLON;
    
    strPrefix = [array objectAtIndex:row];
    
    [self setCategoryButtonText:strPrefix];
    
    if (self.categoryPopupPicker)
    {
        [self.categoryPopupPicker removeFromSuperview];
        self.categoryPopupPicker = nil;
    }
    [self blockUser:FALSE];
}

- (void)blockUser:(BOOL)bBlock
{
    self.buttonBlocker.hidden = !bBlock;
}

- (IBAction)buttonBlockerTouched:(id)sender
{
    [self blockUser:NO];
    [self resignAllResponders];
    [self.categoryPopupPicker removeFromSuperview];
}

- (IBAction)AdvancedDetails
{
    [self resignAllResponders];

    //spawn infoView
    InfoView *iv = [InfoView CreateWithDelegate:self];
    iv.frame = self.view.bounds;
    
    NSString* path = [[NSBundle mainBundle] pathForResource:@"transactionDetails" ofType:@"html"];
    NSString* content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];

    uint64_t totalSent = 0;
    uint64_t fees = self.transaction.minerFees + self.transaction.abFees;

    NSMutableString *inAddresses = [[NSMutableString alloc] init];
    NSMutableString *outAddresses = [[NSMutableString alloc] init];
    NSMutableString *baseUrl = [[NSMutableString alloc] init];
    if ([CoreBridge isTestNet]) {
        [baseUrl appendString:@"https://www.biteasy.com/testnet"];
    } else {
        [baseUrl appendString:@"https://insight.bitpay.com"];
    }
    for (TxOutput *t in self.transaction.outputs) {
        NSString *val = [CoreBridge formatSatoshi:t.value];
        NSString *html;
        if ([CoreBridge isTestNet]) {
            html = [NSString stringWithFormat:@("<div class=\"wrapped\"><a href=\"%@/addresses/%@\">%@</a></div><div>%@</div>"),
                            baseUrl, t.strAddress, t.strAddress, val];
        } else {
            html = [NSString stringWithFormat:@("<div class=\"wrapped\"><a href=\"%@/address/%@\">%@</a></div><div>%@</div>"),
                            baseUrl, t.strAddress, t.strAddress, val];
        }
        if (t.bInput) {
            [inAddresses appendString:html];
            totalSent += t.value;
        } else {
            [outAddresses appendString:html];
        }
    }
    totalSent -= fees;
    NSString *txIdLink;

    if ([CoreBridge isTestNet]) {
        txIdLink = [NSString stringWithFormat:@"<div class=\"wrapped\"><a href=\"%@/transactions/%@\">%@</a></div>",
                                              baseUrl, self.transaction.strMallealbeID, self.transaction.strMallealbeID];
    } else {
        txIdLink = [NSString stringWithFormat:@"<div class=\"wrapped\"><a href=\"%@/tx/%@\">%@</a></div>",
                                              baseUrl, self.transaction.strMallealbeID, self.transaction.strMallealbeID];
    }
    //transaction ID
    content = [content stringByReplacingOccurrencesOfString:@"*1" withString:txIdLink];
    //Total sent
    content = [content stringByReplacingOccurrencesOfString:@"*2" withString:[CoreBridge formatSatoshi:totalSent]];
    //source
    content = [content stringByReplacingOccurrencesOfString:@"*3" withString:inAddresses];
    //Destination
    content = [content stringByReplacingOccurrencesOfString:@"*4" withString:outAddresses];
    //Miner Fee
    content = [content stringByReplacingOccurrencesOfString:@"*5" withString:[CoreBridge formatSatoshi:fees]];
    iv.htmlInfoToDisplay = content;
    [self.view addSubview:iv];
}

- (IBAction)buttonInfoTouched:(id)sender
{
    [self resignAllResponders];
    [InfoView CreateWithHTML:@"infoTransactionDetails" forView:self.view];
}

- (IBAction)imagePhotoTouched:(id)sender
{
    if (0 != _bizId)
    {
        NSString *biz = [NSString stringWithFormat:@"%u", _bizId];
        CLLocation *location = [Location controller].curLocation;
        [self launchBusinessDetailsWithBizID:biz andLocation:location.coordinate animated:YES];
    }
}

- (void)launchBusinessDetailsWithBizID: (NSString *)bizId andLocation: (CLLocationCoordinate2D)location animated: (BOOL)animated
{
    if (businessDetailsController)
    {
        return;
    }
    
    UIStoryboard *mainStoryboard = [UIStoryboard storyboardWithName: @"Main_iPhone" bundle: nil];
    businessDetailsController = [mainStoryboard instantiateViewControllerWithIdentifier: @"BusinessDetailsViewController"];
    
    businessDetailsController.bizId = bizId;
    businessDetailsController.latLong = location;
    businessDetailsController.delegate = self;
    
    CGRect frame = self.view.bounds;
    frame.origin.x = frame.size.width;
    businessDetailsController.view.frame = frame;
    [self.view addSubview: businessDetailsController.view];
    
    if (animated)
    {
        [[UIApplication sharedApplication] beginIgnoringInteractionEvents];
        [UIView animateWithDuration: 0.35
                              delay: 0.0
                            options: UIViewAnimationOptionCurveEaseInOut
                         animations: ^
         {
             businessDetailsController.view.frame = self.view.bounds;
         }
                         completion: ^(BOOL finished)
         {
             [[UIApplication sharedApplication] endIgnoringInteractionEvents];
             //self.dividerView.alpha = 0.0;
         }];
    }
}

- (void)dismissBusinessDetails
{
     [businessDetailsController.view removeFromSuperview];
     businessDetailsController = nil;
}

#pragma mark BusinessDetailsViewControllerDelegates

- (void)businessDetailsViewControllerDone: (BusinessDetailsViewController *)controller
{
    [UIView animateWithDuration: 0.35
                          delay: 0.0
                        options: UIViewAnimationOptionCurveEaseInOut
                     animations: ^
     {
         CGRect frame = self.view.bounds;
         frame.origin.x = frame.size.width;
         businessDetailsController.view.frame = frame;
     }
                     completion: ^(BOOL finished)
     {
         [self dismissBusinessDetails];
     }];
}

#pragma mark - Misc Methods

- (void)updateDisplayLayout
{
}

- (void)updatePhoto
{
    BOOL bHavePhoto = NO;

    // look for the name in our images
    UIImage *imageForPhoto = [self.dictImages objectForKey:self.nameTextField.text];
    if (imageForPhoto)
    {
        self.imagePhoto.image = imageForPhoto;
        self.imagePhoto.layer.cornerRadius = 5;
        self.imagePhoto.layer.masksToBounds = YES;
        bHavePhoto = YES;
    }

    self.imagePhoto.hidden = !bHavePhoto;
    self.photo = imageForPhoto;
}

- (void)updateBizId
{
    _bizId = 0;
    NSNumber *numBizId = [self.dictBizIds objectForKey:self.nameTextField.text];
    if (numBizId)
    {
        _bizId = [numBizId intValue];
    }
}

- (void)generateListOfNearBusinesses
{
    // create the search query
    NSMutableString *strURL = [[NSMutableString alloc] init];
    [strURL appendString:[NSString stringWithFormat:@"%@/search/?radius=%d&sort=%d", SERVER_API, SEARCH_RADIUS, SORT_RESULT_DISTANCE]];

    // add our location
    [self addLocationToQuery:strURL];

    // run the search
    [self issueRequests:@{strURL : [NSNumber numberWithInt:RequestType_BusinessesNear]} ];
}

- (void)generateListOfContactNames
{
    NSMutableArray *arrayContacts = [[NSMutableArray alloc] init];

    CFErrorRef error;
    ABAddressBookRef addressBook = ABAddressBookCreateWithOptions(NULL, &error);

    __block BOOL accessGranted = NO;

    if (ABAddressBookRequestAccessWithCompletion != NULL)
    {
        // we're on iOS 6
        dispatch_semaphore_t sema = dispatch_semaphore_create(0);

        ABAddressBookRequestAccessWithCompletion(addressBook, ^(bool granted, CFErrorRef error)
                                                 {
                                                     accessGranted = granted;
                                                     dispatch_semaphore_signal(sema);
                                                 });

        dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
        //dispatch_release(sema);
    }
    else
    {
        // we're on iOS 5 or older
        accessGranted = YES;
    }

    if (accessGranted)
    {
        CFArrayRef people = ABAddressBookCopyArrayOfAllPeople(addressBook);
        for (CFIndex i = 0; i < CFArrayGetCount(people); i++)
        {
            ABRecordRef person = CFArrayGetValueAtIndex(people, i);

            NSString *strFullName = [Util getNameFromAddressRecord:person];
            if ([strFullName length])
            {
                if ([arrayContacts indexOfObject:strFullName] == NSNotFound)
                {
                    // add this contact
                    [arrayContacts addObject:strFullName];

                    // does this contact has an image
                    if (ABPersonHasImageData(person))
                    {
                        NSData *data = (__bridge_transfer NSData*)ABPersonCopyImageData(person);
                        if(data)
                        {
                            [self.dictImages setObject:[UIImage imageWithData:data] forKey:strFullName];
                        }
                    }
                }
            }
        }
        CFRelease(people);
    }

    // store the final
    self.arrayContacts = arrayContacts;
    //NSLog(@"contacts: %@", self.arrayContacts);
}

- (UIImage *)stretchableImage:(NSString *)imageName
{
    UIImage *img = [UIImage imageNamed:imageName];
    UIImage *stretchable = [img resizableImageWithCapInsets:UIEdgeInsetsMake(10,10,10,10)]; //top, left, bottom, right
    return stretchable;
}

- (void)scrollContentViewToFrame:(CGRect)newFrame
{
    [UIView animateWithDuration:0.35
                          delay: 0.0
                        options: UIViewAnimationOptionCurveEaseOut
                     animations:^
     {
         self.scrollableContentView.frame = newFrame;
     }
                     completion:^(BOOL finished)
     {

     }];
}

- (void)scrollContentViewBackToOriginalPosition
{
    [UIView animateWithDuration:0.35
                          delay: 0.0
                        options: UIViewAnimationOptionCurveEaseOut
                     animations:^
     {
         self.headerView.frame = _originalHeaderFrame;
         self.contentView.frame = _originalContentFrame;
         self.scrollableContentView.frame = _originalScrollableContentFrame;
     }
     completion:^(BOOL finished)
     {
     }];
}

// returns which prefix the given string starts with
// returns nil if none of them
- (NSString *)categoryPrefix:(NSString *)strCategory
{
    NSString *strPrefix;
    if (strCategory)
    {
        for (strPrefix in ARRAY_CATEGORY_PREFIXES)
        {
            if ([strCategory hasPrefix:strPrefix])
            {
                strPrefix = [strPrefix stringByReplacingOccurrencesOfString:@":" withString:@""];
                return strPrefix;
            }
        }
    }

    return nil;
}

- (NSString *)categoryPrefixRemove:(NSString *)strCategory
{
    
    NSArray *arrayTypes = ARRAY_CATEGORY_PREFIXES;
    
    for (NSString *strPrefix in arrayTypes)
    {
        if ([strCategory hasPrefix:strPrefix])
        {
            NSRange rOriginal = [strCategory rangeOfString: strPrefix];
            if (NSNotFound != rOriginal.location) {
                strCategory = [strCategory
                               stringByReplacingCharactersInRange: rOriginal
                               withString:@""];
                return strCategory;
            }
        }
    }
    
    return nil;
}

- (void)addMatchesToArray:(NSMutableArray *)arrayMatches forCategoryType:(NSString *)strPrefix withMatchesFor:(NSString *)strMatch inArray:(NSArray *)arraySource
{
    for (NSString *strCategory in arraySource)
    {
        if ([strCategory hasPrefix:strPrefix])
        {
            BOOL bAddIt = YES;

            if ([strMatch length])
            {
                bAddIt = NO;
                // if the string is long enough
                if ([strCategory length] >= [strPrefix length] + [strMatch length])
                {
                    // search for it
                    NSRange searchRange;
                    searchRange.location = [strPrefix length];
                    searchRange.length = [strCategory length] - [strPrefix length];
                    NSRange range = [strCategory rangeOfString:strMatch options:NSCaseInsensitiveSearch range:searchRange];
                    if (range.location != NSNotFound)
                    {
                        bAddIt = YES;
                    }
                }
            }
            if (bAddIt)
            {
                [arrayMatches addObject:strCategory];
            }
        }
    }
}

- (NSArray *)createNewCategoryChoices:(NSString *)strVal
{
    NSMutableArray *arrayChoices = [[NSMutableArray alloc] init];

    // start with the value given
    NSMutableString *strCurVal = [[NSMutableString alloc] initWithString:@""];
    if (strVal)
    {
        if ([strVal length])
        {
            [strCurVal setString:strVal];
        }
    }

    // remove the prefix if it exists
    NSString *strPrefix = [self categoryPrefix:strCurVal];
    if (strPrefix)
    {
        [strCurVal setString:[self categoryPrefixRemove:strCurVal]];
    }

    NSString *strFirstType = @"Expense:";
    NSString *strSecondType = @"Income:";
    NSString *strThirdType = @"Transfer:";
    NSString *strFourthType = @"Exchange:"; 

    if (self.transactionDetailsMode == TD_MODE_RECEIVED ||
        [self.categoryButton.titleLabel.text isEqual:@"Income"])
    {
        strFirstType = @"Income:";
        strSecondType = @"Expense:";
    }
    
    if ([self.categoryButton.titleLabel.text isEqual:@"Transfer"])
    {
        strFirstType = @"Transfer:";
        strSecondType = @"Expense:";
        strThirdType = @"Income:";
        strFourthType = @"Exchange:";
    }

    if ([self.categoryButton.titleLabel.text isEqual:@"Exchange"])
    {
        strFirstType =  @"Exchange:";
        strSecondType = @"Expense:";
        strThirdType = @"Income:";
        strFourthType = @"Transfer:";
    }
    
    NSArray *arrayTypes = @[strFirstType, strSecondType, strThirdType, strFourthType];

    // run through each type
    for (NSString *strPrefix in arrayTypes)
    {
        [self addMatchesToArray:arrayChoices forCategoryType:strPrefix withMatchesFor:strCurVal inArray:self.arrayCategories];
    }

    // add the choices constructed with the current string
    for (NSString *strPrefix in arrayTypes)
    {
        NSString *strCategory = [NSString stringWithFormat:@"%@%@", strPrefix, strCurVal];

        // if it isn't already in our array
        if (NSNotFound == [arrayChoices indexOfObject:strCategory])
        {
            [arrayChoices addObject:strCategory];
        }
    }

    return arrayChoices;
}

- (void)forceCategoryFieldValue:(UITextField *)textField forPickerView:(PickerTextView *)pickerTextView
{
    NSMutableString *strNewVal = [[NSMutableString alloc] init];
    strNewVal = (NSMutableString *) [self categoryPrefixRemove:textField.text];

    NSString *strPrefix = [self categoryPrefix:textField.text];

    NSArray *arrayChoices = [self createNewCategoryChoices:textField.text];
    [pickerTextView updateChoices:arrayChoices];
    
    if (strNewVal)
    {
        textField.text = strNewVal;
    }
    
    // If string starts with a prefix, then set category button to prefix
    if (strPrefix != nil)
    {
        [self setCategoryButtonText:strPrefix];
    }
}

- (void)resignAllResponders
{
    [self.notesTextView resignFirstResponder];
    [self.pickerTextCategory.textField resignFirstResponder];
    [self.nameTextField resignFirstResponder];
    [self.fiatTextField resignFirstResponder];
    [self.categoryPopupPicker resignFirstResponder];
    [self dismissPayeeTable];
    [self scrollContentViewBackToOriginalPosition];
}

- (void)loadCategories
{
    char            **aszCategories = NULL;
    unsigned int    countCategories = 0;

    // get the categories from the core
    tABC_Error Error;
    ABC_GetCategories([[User Singleton].name UTF8String],
                      [[User Singleton].password UTF8String],
                      &aszCategories,
                      &countCategories,
                      &Error);
    [Util printABC_Error:&Error];

    // store them in our own array
    NSMutableArray *arrayCategories = [[NSMutableArray alloc] init];
    if (aszCategories)
    {
        for (int i = 0; i < countCategories; i++)
        {
            [arrayCategories addObject:[NSString stringWithUTF8String:aszCategories[i]]];
        }
    }

    // store the final as storted
    self.arrayCategories = [arrayCategories sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];

    // free the core categories
    if (aszCategories != NULL)
    {
        [Util freeStringArray:aszCategories count:countCategories];
    }
}

- (void)addCategory:(NSString *)strCategory
{
    // check and see if there is more text than just the prefix
    //if ([ARRAY_CATEGORY_PREFIXES indexOfObject:strCategory] == NSNotFound)
    {
        // check and see that it doesn't already exist
        if ([self.arrayCategories indexOfObject:strCategory] == NSNotFound)
        {
            // add the category to the core
            tABC_Error Error;
            ABC_AddCategory([[User Singleton].name UTF8String],
                            [[User Singleton].password UTF8String],
                            (char *)[strCategory UTF8String], &Error);
            [Util printABC_Error:&Error];
        }
    }
}

- (void)updateAutoCompleteArray
{
    if (_autoCompleteTable)
    {
        // if there is anything in the payee field
        if ([self.nameTextField.text length])
        {
            NSString *strTerm = self.nameTextField.text;

            NSMutableArray *arrayAutoComplete = [[NSMutableArray alloc] init];

            // go through all the near businesses
            for (NSString *strBusiness in self.arrayNearBusinesses)
            {
                // if it matches what the user has currently typed
                if ([strBusiness rangeOfString:strTerm options:NSCaseInsensitiveSearch].location != NSNotFound)
                {
                    // add this business to the auto complete array
                    [arrayAutoComplete addObject:strBusiness];

                    // make sure we have the thumbnail
                    [self ifNeededResolveThumbnailForBusiness:strBusiness];
                }
            }

            // go through all the contacts
            for (NSString *strContact in self.arrayContacts)
            {
                // if it matches what the user has currently typed
                if ([strContact rangeOfString:strTerm options:NSCaseInsensitiveSearch].location != NSNotFound)
                {
                    [arrayAutoComplete addObject:strContact];
                }
            }

            // check if we have less than the minimum
            if ([arrayAutoComplete count] < MIN_AUTOCOMPLETE)
            {
                // add the matches from other busineses
                for (NSString *strBusiness in self.arrayOtherBusinesses)
                {
                    // if it matches what the user has currently typed
                    if ([strBusiness rangeOfString:strTerm options:NSCaseInsensitiveSearch].location != NSNotFound)
                    {
                        // if it isn't already in the near array
                        if (![self.arrayNearBusinesses containsObject:strBusiness])
                        {
                            // add this business to the auto complete array
                            [arrayAutoComplete addObject:strBusiness];

                            // make sure we have the thumbnail
                            [self ifNeededResolveThumbnailForBusiness:strBusiness];
                        }
                    }
                }

                // issue an auto-complete request for it
                [self getAutoCompleteResultsFor:strTerm];
            }

            self.arrayAutoComplete = [arrayAutoComplete sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
        }
        else
        {
            if (self.transactionDetailsMode == TD_MODE_RECEIVED)
            {
                // this is a receive so use the address book
                self.arrayAutoComplete = self.arrayContacts;
            }
            else
            {
                // this is a sent so we must be looking for businesses

                // since nothing in payee yet, just populate with businesses (already sorted by distance)
                self.arrayAutoComplete = self.arrayNearBusinesses;

                // make sure we have the thumbnails for all of these businesses
                for (NSString *strName in self.arrayNearBusinesses)
                {
                    [self ifNeededResolveThumbnailForBusiness:strName];
                }
            }
        }

        // initiate any thumbnail resolves
        [self resolveOutstandingThumbnails];

        // force the table to reload itself
        [self reloadAutoCompleteTable];
    }
}

- (void)reloadAutoCompleteTable
{
    [_autoCompleteTable reloadData];
}

- (void)resolveOutstandingThumbnails
{
    for (int i = (int) [self.arrayThumbnailsToRetrieve count] - 1; i >= 0; i--)
    {
        NSString *strName = [self.arrayThumbnailsToRetrieve objectAtIndex:i];
        [self getThumbnailForBusiness:strName];
        [self.arrayThumbnailsToRetrieve removeObjectAtIndex:i];
    }
}

- (void)ifNeededResolveThumbnailForBusiness:(NSString *)strName
{
    // if we don't already have it, it isn't being resolved and it isn't queued to be resolved
    if ((nil == [self.dictImages objectForKey:strName]) &&
        (NO == [self.arrayThumbnailsRetrieving containsObject:strName]) &&
        (NO == [self.arrayThumbnailsToRetrieve containsObject:strName]))
    {
        // add it to those to retrieve
        [self.arrayThumbnailsToRetrieve addObject:strName];
    }
}

- (void)getThumbnailForBusiness:(NSString *)strName
{
    NSString *strThumbnailURL = [self.dictThumbnailURLs objectForKey:strName];

    if (strThumbnailURL)
    {
        [self.arrayThumbnailsRetrieving addObject:strName];

        // create the search query
        NSString *strURL = [NSString stringWithFormat:@"%@%@", SERVER_URL, strThumbnailURL];

        // run the query - note we are using perform selector so it is handled on a seperate run of the run loop to avoid callback issues
        [self performSelector:@selector(issueRequests:) withObject:@{ strURL : strName } afterDelay:0.0];
    }
}

- (void)addLocationToQuery:(NSMutableString *)query
{
    if ([query rangeOfString:@"&ll="].location == NSNotFound)
    {
        CLLocation *location = [Location controller].curLocation;
        if(location) //can be nil if user has locationServices turned off
        {
            NSString *locationString = [NSString stringWithFormat:@"%f,%f", location.coordinate.latitude, location.coordinate.longitude];
            [query appendFormat:@"&ll=%@", locationString];
        }
    }
    else
    {
        //NSLog(@"string already contains ll");
    }
}

- (void)getAutoCompleteResultsFor:(NSString *)strName
{
    // if we haven't already run this query
    if (NO == [self.arrayAutoCompleteQueries containsObject:strName])
    {
        [self.arrayAutoCompleteQueries addObject:strName];

        NSString *strURL = [NSString stringWithFormat: @"%@/autocomplete-business/?term=%@", SERVER_API, strName];
        // run the search - note we are using perform selector so it is handled on a seperate run of the run loop to avoid callback issues
        [self performSelector:@selector(issueRequests:) withObject:@{strURL : [NSNumber numberWithInt:RequestType_BusinessesAuto]} afterDelay:0.0];
    }
}

- (void)getBizDetailsForBizId:(unsigned int)bizId
{
    // create the search query
    NSString *strURL = [NSString stringWithFormat:@"%@/business/%u/", SERVER_API, bizId];

    // run the search - note we are using perform selector so it is handled on a seperate run of the run loop to avoid callback issues
    [self performSelector:@selector(issueRequests:) withObject:@{strURL : [NSNumber numberWithInt:RequestType_BusinessDetails]} afterDelay:0.0];
}

- (void)issueRequests:(NSDictionary *)dictRequest
{
    if (dictRequest)
    {
        // the requests are stored in a dictionary where the key is the URL and the value for the key is the object for callback
        for (NSString *strKey in dictRequest)
        {
            id value = [dictRequest objectForKey:strKey];

            // run the search
            NSString *strURL = [strKey stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
            [[DL_URLServer controller] issueRequestURL:strURL
                                            withParams:nil
                                            withObject:value
                                          withDelegate:self
                                    acceptableCacheAge:CACHE_AGE_SECS
                                           cacheResult:YES];
        }
    }
}

- (void)installLeftToRightSwipeDetection
{
    UISwipeGestureRecognizer *gesture = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(didSwipeLeftToRight:)];
    gesture.direction = UISwipeGestureRecognizerDirectionRight;
    [self.view addGestureRecognizer:gesture];
}

// used by the guesture recognizer to ignore exit
- (BOOL)haveSubViewsShowing
{
    return NO;
}

- (void)exit:(BOOL)bNotifyExit
{
    // if we haven't closed already
    if (!_bDoneSentToDelegate)
    {
        _bDoneSentToDelegate = YES;
        [self.delegate TransactionDetailsViewControllerDone:self];
        if (bNotifyExit) {
            NSDictionary *dictNotification = @{ KEY_TX_DETAILS_EXITED_TX            : self.transaction,
                                                KEY_TX_DETAILS_EXITED_WALLET_UUID   : self.transaction.strWalletUUID,
                                                KEY_TX_DETAILS_EXITED_WALLET_NAME   : self.transaction.strWalletName,
                                                KEY_TX_DETAILS_EXITED_TX_ID         : self.transaction.strID
                                                };
            [[NSNotificationCenter defaultCenter] postNotificationName:NOTIFICATION_TRANSACTION_DETAILS_EXITED object:self userInfo:dictNotification];
        }
    }
}

#pragma mark - Calculator delegates

- (void)CalculatorDone:(CalculatorView *)calculator
{
    [self.fiatTextField resignFirstResponder];

    double amountFiat = [[self.fiatTextField text] doubleValue];
    
    if (_transactionDetailsMode == TD_MODE_SENT)
    {
        if (amountFiat > 0)
        {
            // Make amount negative since calculator cant work with negative values
            amountFiat *= -1;
            self.fiatTextField.text = [NSString stringWithFormat:@"%f", amountFiat];
        }
    }
    
    

}

- (void)CalculatorValueChanged:(CalculatorView *)calculator
{
//    NSLog(@"calc change. Field now: %@ (%@)", self.fiatTextField.text, calculator.textField.text);

}

#pragma mark - Payee Table

- (void)spawnPayeeTableInFrame:(CGRect)frame
{
    CGRect startingFrame = frame;
    startingFrame.size.height = 0;
    _autoCompleteTable = [[UITableView alloc] initWithFrame:startingFrame];
    _autoCompleteTable.backgroundColor = TABLE_CELL_BACKGROUND_COLOR;
    _autoCompleteTable.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];     // This will remove extra separators from tableview
    [self.view addSubview:_autoCompleteTable];
    
    _autoCompleteTable.dataSource = self;
    _autoCompleteTable.delegate = self;
    
    [UIView animateWithDuration:0.35
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseInOut
                     animations:^
     {
         _autoCompleteTable.frame = frame;
     }
     completion:^(BOOL finished)
     {
         
     }];
}

- (void)dismissPayeeTable
{
    if (_autoCompleteTable)
    {
        CGRect frame = _autoCompleteTable.frame;
        frame.size.height = 0.0;
        frame.origin.y = frame.origin.y + 100;// (_originalScrollableContentFrame.origin.y - self.scrollableContentView.frame.origin.y);
        [UIView animateWithDuration:0.35
                              delay:0.0
                            options:UIViewAnimationOptionCurveEaseInOut
                         animations:^
         {
             _autoCompleteTable.frame = frame;
         }
                         completion:^(BOOL finished)
         {
             [_autoCompleteTable removeFromSuperview];
             _autoCompleteTable = nil;
         }];
    }
}

#pragma mark - UITableView delegates

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [self.arrayAutoComplete count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *cellIdentifier = @"PayeeCell";
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    
    //5.1 you do not need this if you have set SettingsCell as identifier in the storyboard (else you can remove the comments on this code)
    if (cell == nil)
    {
        cell = [[PayeeCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellIdentifier];
    }
    
    cell.textLabel.text = [self.arrayAutoComplete objectAtIndex:indexPath.row];
    cell.backgroundColor = TABLE_CELL_BACKGROUND_COLOR;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    // address
    cell.detailTextLabel.text = [self.dictAddresses objectForKey:cell.textLabel.text];

    // image
    UIImage *imageForCell = [self.dictImages objectForKey:cell.textLabel.text];
    if (imageForCell == nil)
    {
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(1, 1), NO, 0.0);
        imageForCell = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    }
    cell.imageView.image = imageForCell;

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    self.nameTextField.text = [self.arrayAutoComplete objectAtIndex:indexPath.row];
    
    // dismiss the tableView
    [self.nameTextField resignFirstResponder];
    [self dismissPayeeTable];
    if (!self.bOldTransaction)
    {
        [self.pickerTextCategory.textField becomeFirstResponder];
    }

    [self updateBizId];
    [self updatePhoto];
}


#pragma mark - infoView delegates

-(void)InfoViewFinished:(InfoView *)infoView
{
    [infoView removeFromSuperview];
}

#pragma mark - DLURLServer Callbacks

- (void)onDL_URLRequestCompleteWithStatus:(tDL_URLRequestStatus)status resultData:(NSData *)data resultObj:(id)object
{
    if (DL_URLRequestStatus_Success == status)
    {
        // if this is a business listing query
        if ([object isKindOfClass:[NSNumber class]])
        {
            NSNumber *numRequestType = (NSNumber *)object;
            tRequestType requestType = (tRequestType) [numRequestType intValue];

            NSString *jsonString = [[NSString alloc] initWithBytes:[data bytes] length:[data length] encoding:NSUTF8StringEncoding];

            //NSLog(@"Results download returned: %@", jsonString );

            NSData *jsonData = [jsonString dataUsingEncoding:NSUTF32BigEndianStringEncoding];
            NSError *myError;
            NSDictionary *dictFromServer = [[CJSONDeserializer deserializer] deserializeAsDictionary:jsonData error:&myError];

            NSArray *searchResultsArray = [dictFromServer objectForKey:@"results"];
            if (searchResultsArray && searchResultsArray != (id)[NSNull null])
            {
                if (requestType == RequestType_BusinessesAuto)
                {
                    for (NSDictionary *dict in searchResultsArray)
                    {
                        NSString *strName = [dict objectForKey:@"text"];
                        if (strName && strName != (id)[NSNull null])
                        {
                            // if it doesn't exist in the other, add it
                            if (NO == [self.arrayOtherBusinesses containsObject:strName])
                            {
                                [self.arrayOtherBusinesses addObject:strName];
                            }

                            // set the biz id if available
                            NSNumber *numBizId = [dict objectForKey:@"bizId"];
                            if (numBizId && numBizId != (id)[NSNull null])
                            {
                                [self.dictBizIds setObject:[NSNumber numberWithInt:[numBizId intValue]] forKey:strName];
                            }

                            NSString *strThumbnail = [dict objectForKey:@"square_image"];
                            if (strThumbnail && strThumbnail != (id)[NSNull null]) {
                                [self.dictThumbnailURLs setObject:strThumbnail forKey:strName];
                            }
                        }
                    }
                }
                else if (requestType == RequestType_BusinessesNear)
                {
                    NSMutableArray *arrayBusinesses = self.arrayNearBusinesses;

                    for (NSDictionary *dict in searchResultsArray)
                    {
                        NSString *strName = [dict objectForKey:@"name"];
                        if (strName && strName != (id)[NSNull null])
                        {
                            [arrayBusinesses addObject:strName];

                            // create the address
                            NSMutableString *strAddress = [[NSMutableString alloc] init];
                            NSString *strField = nil;
                            if (nil != (strField = [dict objectForKey:@"address"]))
                            {
                                [strAddress appendString:strField];
                            }
                            if (nil != (strField = [dict objectForKey:@"city"]))
                            {
                                [strAddress appendFormat:@"%@%@", ([strAddress length] ? @", " : @""), strField];
                            }
                            if (nil != (strField = [dict objectForKey:@"state"]))
                            {
                                [strAddress appendFormat:@"%@%@", ([strAddress length] ? @", " : @""), strField];
                            }
                            if (nil != (strField = [dict objectForKey:@"postalcode"]))
                            {
                                [strAddress appendFormat:@"%@%@", ([strAddress length] ? @" " : @""), strField];
                            }
                            if ([strAddress length])
                            {
                                [self.dictAddresses setObject:strAddress forKey:strName];
                            }

                            // set the biz id if available
                            NSNumber *numBizId = [dict objectForKey:@"bizId"];
                            if (numBizId && numBizId != (id)[NSNull null])
                            {
                                [self.dictBizIds setObject:[NSNumber numberWithInt:[numBizId intValue]] forKey:strName];
                            }

                            // check if we can get a thumbnail
                            NSDictionary *dictProfileImage = [dict objectForKey:@"square_image"];
                            if (dictProfileImage && dictProfileImage != (id)[NSNull null])
                            {
                                NSString *strThumbnail = [dictProfileImage objectForKey:@"thumbnail"];
                                if (strThumbnail && strThumbnail != (id)[NSNull null])
                                {
                                    //NSLog(@"thumbnail path: %@", strThumbnail);
                                    [self.dictThumbnailURLs setObject:strThumbnail forKey:strName];
                                }
                            }
                        }
                    }
                }

                // update the auto complete array because we just added new businesses
                [self performSelector:@selector(updateAutoCompleteArray) withObject:nil afterDelay:0.0];

                // update the biz id (in case we found one for our business)
                [self performSelector:@selector(updateBizId) withObject:nil afterDelay:0.0];
            }
        }
        else if ([object isKindOfClass:[NSString class]])
        {
            NSString *strNameForImage = (NSString *) object;
            //NSLog(@"\n❎❎❎❎❎❎❎❎❎❎❎❎❎❎❎❎\ngot image for %@\n❎❎❎❎❎❎❎❎❎❎❎❎❎❎❎❎", strNameForImage);
            
            // remove it from our array of thumbnails we are currently retrieving
            [self.arrayThumbnailsRetrieving removeObject:strNameForImage];

            // if we don't have an image for this yet
            if (nil == [self.dictImages objectForKey:strNameForImage])
            {
                UIImage *srcImage = [UIImage imageWithData:data];
                [self.dictImages setObject:srcImage forKey:strNameForImage];

                // reload the table so it can get at the image if it needs it
                [self performSelector:@selector(reloadAutoCompleteTable) withObject:nil afterDelay:0.0];

                // if this matches our name
                if ([self.nameTextField.text isEqualToString:strNameForImage])
                {
                    // update the photo
                    [self performSelector:@selector(updatePhoto) withObject:nil afterDelay:0.0];
                }
            }
        }
    }
}

#pragma mark - UITextView delegates

- (BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text
{
    if ([text isEqualToString:(NSString *) @"\n"])
    {
        CGRect scrollFrame = self.scrollableContentView.frame;

        [self scrollContentViewToFrame:scrollFrame];
        [textView resignFirstResponder];
    }
    return YES;
}

- (void)textViewDidBeginEditing:(UITextView *)textView
{
    _activeTextView = textView;
    
    CGRect scrollFrame = self.scrollableContentView.frame;
    
    if (textView == self.notesTextView)
    {
        scrollFrame.origin.y = -self.notesTextView.frame.origin.y + 30;
        [self dismissPayeeTable];
    }
    
    [self scrollContentViewToFrame:scrollFrame];
}

#pragma mark - UITextField delegates

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string
{
    return YES;
}


- (void)textFieldDidBeginEditing:(UITextField *)textField
{
    _activeTextField = textField;

    CGRect scrollFrame = self.scrollableContentView.frame;

    // WARNING: Lots of magic numbers - but we have to make this change quick for the demo

    if (textField == self.nameTextField)
    {
        scrollFrame.origin.y = -self.nameTextField.frame.origin.y + 10;

        CGRect frame = self.view.bounds;
        frame.origin.y = 100;
        frame.size.height = 252;
        [self spawnPayeeTableInFrame:frame];
        [self updateAutoCompleteArray];
    }
    else
    {
        scrollFrame.origin.y = _originalScrollableContentFrame.origin.y;
    }

    [self scrollContentViewToFrame:scrollFrame];

    // highlight all the text
    [textField setSelectedTextRange:[textField textRangeFromPosition:textField.beginningOfDocument toPosition:textField.endOfDocument]];
}

- (void)textFieldDidEndEditing:(UITextField *)textField
{
    // unhighlight text
    // note: for some reason, if we don't do this, the text won't select next time the user selects it
    [textField setSelectedTextRange:[textField textRangeFromPosition:textField.beginningOfDocument toPosition:textField.beginningOfDocument]];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [textField resignFirstResponder];

    if (textField == self.nameTextField)
    {
        [self dismissPayeeTable];
        if (!self.bOldTransaction)
        {
            [self.pickerTextCategory.textField becomeFirstResponder];
        }
    }
    
    return YES;
}

- (void)textFieldDidChange:(UITextField *)textField
{
    if (textField == self.nameTextField)
    {
        [self updateAutoCompleteArray];
        [self updateBizId];
        [self updatePhoto];
    }
}

#pragma mark - PickerTextView Delegates

- (BOOL)pickerTextViewFieldShouldChange:(PickerTextView *)pickerTextView charactersInRange:(NSRange)range replacementString:(NSString *)string
{
    return YES;
}

- (void)pickerTextViewFieldDidChange:(PickerTextView *)pickerTextView
{
    NSArray *arrayChoices;
    NSMutableString *strNewVal = [[NSMutableString alloc] init];
    
    [strNewVal appendString:pickerTextView.textField.text];

    NSString *strPrefix = [self categoryPrefix:pickerTextView.textField.text];

    if (strPrefix == nil)
    {
        NSMutableString *strFullCategory = [[NSMutableString alloc] init];
        [strFullCategory appendString:self.categoryButton.titleLabel.text];
        [strFullCategory appendString:@":"];
        [strFullCategory appendString:pickerTextView.textField.text];

        arrayChoices = [self createNewCategoryChoices:strFullCategory];
    }
    else
    {
        arrayChoices = [self createNewCategoryChoices:pickerTextView.textField.text];
    }
    
    [pickerTextView updateChoices:arrayChoices];

    pickerTextView.textField.text = strNewVal;

    // If starts with prefix, put prefix in category button
    if (strPrefix != nil)
    {
        [self setCategoryButtonText:strPrefix];
    }

}

- (void)pickerTextViewFieldDidBeginEditing:(PickerTextView *)pickerTextView
{
    _activeTextField = pickerTextView.textField;

    [self forceCategoryFieldValue:pickerTextView.textField forPickerView:pickerTextView];

    // highlight all the text
    /*
    NSRange range = [pickerTextView.textField.text rangeOfString:@":"];
    UITextPosition *startPosition = [pickerTextView.textField positionFromPosition:pickerTextView.textField.beginningOfDocument offset:range.location + 1];
     */
    [pickerTextView.textField setSelectedTextRange:[pickerTextView.textField textRangeFromPosition:pickerTextView.textField.beginningOfDocument toPosition:pickerTextView.textField.endOfDocument]];
}

- (BOOL)pickerTextViewShouldEndEditing:(PickerTextView *)pickerTextView
{
    // unhighlight text
    // note: for some reason, if we don't do this, the text won't select next time the user selects it
    [pickerTextView.textField setSelectedTextRange:[pickerTextView.textField textRangeFromPosition:pickerTextView.textField.beginningOfDocument toPosition:pickerTextView.textField.beginningOfDocument]];

    [self blockUser:FALSE];
    
    return YES;
}

- (void)pickerTextViewFieldDidEndEditing:(PickerTextView *)pickerTextView
{
    //[self forceCategoryFieldValue:pickerTextView.textField forPickerView:pickerTextView];
}

- (BOOL)pickerTextViewFieldShouldReturn:(PickerTextView *)pickerTextView
{
    [pickerTextView.textField resignFirstResponder];

    if (!self.bOldTransaction)
    {
        // XX Don't go to notes. Feels like most users don't use notes most often
//        [self.notesTextView becomeFirstResponder];
    }

    return YES;
}

- (void)pickerTextViewPopupSelected:(PickerTextView *)pickerTextView onRow:(NSInteger)row
{
    // set the text field to the choice
    pickerTextView.textField.text = [pickerTextView.arrayChoices objectAtIndex:row];
    
    NSArray *arrayChoices = [self createNewCategoryChoices:pickerTextView.textField.text];
    [pickerTextView updateChoices:arrayChoices];
    
    NSString *strPrefix = [self categoryPrefix:pickerTextView.textField.text];
    pickerTextView.textField.text = [self categoryPrefixRemove:pickerTextView.textField.text];
    
    // If starts with prefix, put prefix in category button
    if (strPrefix != nil)
    {
        [self setCategoryButtonText:strPrefix];
    }
    
    [pickerTextView.textField resignFirstResponder];
    [self blockUser:FALSE];
}

- (void)pickerTextViewFieldDidShowPopup:(PickerTextView *)pickerTextView
{
    // forces the size of the popup picker on the picker text view to a certain size

    // Note: we have to do this because right now the size will start as max needed but as we dynamically
    //       alter the choices, we may end up with more choices than we originally started with
    //       so we want the table to always be as large as it can be

    // first start the popup pickerit right under the control and squished down
    CGRect frame = self.pickerTextCategory.popupPicker.frame;
    frame.size.height = 20;
    //frame.size.height = 220; // magic number to make it as big as possible
    CGPoint pickerLocationScreen = [pickerTextView.superview convertPoint:pickerTextView.frame.origin toView:nil];
    frame.origin.y = pickerLocationScreen.y + pickerTextView.frame.size.height - 10;
    self.pickerTextCategory.popupPicker.frame = frame;

    // now move the window up so that the category field is at the top
    CGRect scrollFrame = self.scrollableContentView.frame;
    scrollFrame.origin.y = -self.pickerTextCategory.frame.origin.y + 10;
    [self scrollContentViewToFrame:scrollFrame];
    [self blockUser:TRUE];

    // bring the picker up with it
    [UIView animateWithDuration:0.35
                          delay: 0.0
                        options: UIViewAnimationOptionCurveEaseOut
                     animations:^
     {
         CGRect frame = self.pickerTextCategory.popupPicker.frame;
         frame.origin.y = 130;
         frame.size.height = 220; // magic number to make it as big as possible
         self.pickerTextCategory.popupPicker.frame = frame;
     }
                     completion:^(BOOL finished)
     {

     }];
}

- (void)pickerTextViewDidTouchAccessory:(PickerTextView *)pickerTextView categoryString:(NSString *)catString
{
    NSString *strPrefix;
    strPrefix = [self categoryPrefix:catString];
    pickerTextView.textField.text = [self categoryPrefixRemove:catString];
    [self setCategoryButtonText:strPrefix];
    
    // add string to categories, update arrays
    NSInteger index = [self.arrayCategories indexOfObject:catString];
    if(index == NSNotFound) {
        NSLog(@"ADD CATEGORY: adding category = %@", catString);
        [self addCategory: catString];
        NSMutableArray *array = [[NSMutableArray alloc] initWithArray:self.arrayCategories];
        [array addObject:catString];
        self.arrayCategories = [array sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
        [pickerTextView setCategories:self.arrayCategories];
        NSArray *arrayChoices = [self createNewCategoryChoices:pickerTextView.textField.text];
        [pickerTextView updateChoices:arrayChoices];
    }
    [pickerTextView dismissPopupPicker];
    [pickerTextView.textField resignFirstResponder];
    [self blockUser:FALSE];
}

#pragma mark - Keyboard callbacks

- (void)keyboardWillShow:(NSNotification *)notification
{
    //NSLog(@"keyboard will show");
}

- (void)keyboardWillHide:(NSNotification *)notification
{
    //NSLog(@"keyboard will hide");

    if (_activeTextField.returnKeyType == UIReturnKeyDone)
    {
        [self scrollContentViewBackToOriginalPosition];
    }
    
    if (_activeTextView == self.notesTextView)
    {
        [self scrollContentViewBackToOriginalPosition];
    }
    _activeTextView = nil;
    _activeTextField = nil;
}

#pragma mark - GestureReconizer methods

- (void)didSwipeLeftToRight:(UIGestureRecognizer *)gestureRecognizer
{
    if (![self haveSubViewsShowing])
    {
        if (!self.buttonBack.hidden)
        {
            [self Done];
        }
    }
}

#pragma mark - Custom Notification Handlers

// called when a tab bar button that is already selected, is reselected again
- (void)tabBarButtonReselect:(NSNotification *)notification
{
    if (![self haveSubViewsShowing])
    {
        if (!self.buttonBack.hidden)
        {
            [self Done];
        }
    }
}

#pragma mark - ABC Alert delegate

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == 1) {
        [[NSNotificationCenter defaultCenter] postNotificationName:NOTIFICATION_LAUNCH_RECOVERY_QUESTIONS object:self];
        [self exit:NO];
    } else {
        [self exit:YES];
    }
}

- (void)alertViewCancel:(UIAlertView *)alertView
{
    [self exit:YES];
}

@end
