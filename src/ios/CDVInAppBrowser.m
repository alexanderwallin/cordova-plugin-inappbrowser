/*
 Licensed to the Apache Software Foundation (ASF) under one
 or more contributor license agreements.  See the NOTICE file
 distributed with this work for additional information
 regarding copyright ownership.  The ASF licenses this file
 to you under the Apache License, Version 2.0 (the
 "License"); you may not use this file except in compliance
 with the License.  You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing,
 software distributed under the License is distributed on an
 "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 KIND, either express or implied.  See the License for the
 specific language governing permissions and limitations
 under the License.
 */

#import "CDVInAppBrowser.h"
#import <Cordova/CDVPluginResult.h>
#import <Cordova/CDVUserAgentUtil.h>

#define    kInAppBrowserTargetSelf @"_self"
#define    kInAppBrowserTargetSystem @"_system"
#define    kInAppBrowserTargetBlank @"_blank"

#define    kInAppBrowserToolbarBarPositionBottom @"bottom"
#define    kInAppBrowserToolbarBarPositionTop @"top"

#define    TOOLBAR_HEIGHT 44.0
#define    LOCATIONBAR_HEIGHT 21.0
#define    FOOTER_HEIGHT ((TOOLBAR_HEIGHT) + (LOCATIONBAR_HEIGHT))

#pragma mark CDVInAppBrowser

@interface CDVInAppBrowser () {
    NSInteger _previousStatusBarStyle;
}
@end

@implementation CDVInAppBrowser

- (CDVInAppBrowser*)initWithWebView:(UIWebView*)theWebView
{
    self = [super initWithWebView:theWebView];
    if (self != nil) {
        _previousStatusBarStyle = -1;
        _callbackIdPattern = nil;
    }

    return self;
}

- (void)onReset
{
    [self close:nil];
}

- (void)close:(CDVInvokedUrlCommand*)command
{
    if (self.inAppBrowserViewController == nil) {
        NSLog(@"IAB.close() called but it was already closed.");
        return;
    }
    // Things are cleaned up in browserExit.
    [self.inAppBrowserViewController close];
}

- (BOOL) isSystemUrl:(NSURL*)url
{
	if ([[url host] isEqualToString:@"itunes.apple.com"]) {
		return YES;
	}

	return NO;
}

- (void)open:(CDVInvokedUrlCommand*)command
{
    CDVPluginResult* pluginResult;

    NSString* url = [command argumentAtIndex:0];
    NSString* target = [command argumentAtIndex:1 withDefault:kInAppBrowserTargetSelf];
    NSString* options = [command argumentAtIndex:2 withDefault:@"" andClass:[NSString class]];

    self.callbackId = command.callbackId;

    if (url != nil) {
        NSURL* baseUrl = [self.webView.request URL];
        NSURL* absoluteUrl = [[NSURL URLWithString:url relativeToURL:baseUrl] absoluteURL];

        if ([self isSystemUrl:absoluteUrl]) {
            target = kInAppBrowserTargetSystem;
        }

        if ([target isEqualToString:kInAppBrowserTargetSelf]) {
            [self openInCordovaWebView:absoluteUrl withOptions:options];
        } else if ([target isEqualToString:kInAppBrowserTargetSystem]) {
            [self openInSystem:absoluteUrl];
        } else { // _blank or anything else
            [self openInInAppBrowser:absoluteUrl withOptions:options];
        }

        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"incorrect number of arguments"];
    }

    [pluginResult setKeepCallback:[NSNumber numberWithBool:YES]];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)openInInAppBrowser:(NSURL*)url withOptions:(NSString*)options
{
    CDVInAppBrowserOptions* browserOptions = [CDVInAppBrowserOptions parseOptions:options];

    if (browserOptions.clearcache) {
        NSHTTPCookie *cookie;
        NSHTTPCookieStorage *storage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
        for (cookie in [storage cookies])
        {
            if (![cookie.domain isEqual: @".^filecookies^"]) {
                [storage deleteCookie:cookie];
            }
        }
    }

    if (browserOptions.clearsessioncache) {
        NSHTTPCookie *cookie;
        NSHTTPCookieStorage *storage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
        for (cookie in [storage cookies])
        {
            if (![cookie.domain isEqual: @".^filecookies^"] && cookie.isSessionOnly) {
                [storage deleteCookie:cookie];
            }
        }
    }

    if (self.inAppBrowserViewController == nil) {
        NSString* originalUA = [CDVUserAgentUtil originalUserAgent];
        self.inAppBrowserViewController = [[CDVInAppBrowserViewController alloc] initWithUserAgent:originalUA prevUserAgent:[self.commandDelegate userAgent] browserOptions: browserOptions];
        self.inAppBrowserViewController.navigationDelegate = self;

        if ([self.viewController conformsToProtocol:@protocol(CDVScreenOrientationDelegate)]) {
            self.inAppBrowserViewController.orientationDelegate = (UIViewController <CDVScreenOrientationDelegate>*)self.viewController;
        }
    }

    [self.inAppBrowserViewController showLocationBar:browserOptions.location];
    [self.inAppBrowserViewController showToolBar:browserOptions.toolbar :browserOptions.toolbarposition];
    if (browserOptions.closebuttoncaption != nil) {
        [self.inAppBrowserViewController setCloseButtonTitle:browserOptions.closebuttoncaption];
    }
    // Set Presentation Style
    UIModalPresentationStyle presentationStyle = UIModalPresentationFullScreen; // default
    if (browserOptions.presentationstyle != nil) {
        if ([[browserOptions.presentationstyle lowercaseString] isEqualToString:@"pagesheet"]) {
            presentationStyle = UIModalPresentationPageSheet;
        } else if ([[browserOptions.presentationstyle lowercaseString] isEqualToString:@"formsheet"]) {
            presentationStyle = UIModalPresentationFormSheet;
        }
    }
    self.inAppBrowserViewController.modalPresentationStyle = presentationStyle;

    // Set Transition Style
    UIModalTransitionStyle transitionStyle = UIModalTransitionStyleCoverVertical; // default
    if (browserOptions.transitionstyle != nil) {
        if ([[browserOptions.transitionstyle lowercaseString] isEqualToString:@"fliphorizontal"]) {
            transitionStyle = UIModalTransitionStyleFlipHorizontal;
        } else if ([[browserOptions.transitionstyle lowercaseString] isEqualToString:@"crossdissolve"]) {
            transitionStyle = UIModalTransitionStyleCrossDissolve;
        }
    }
    self.inAppBrowserViewController.modalTransitionStyle = transitionStyle;

    // prevent webView from bouncing
    if (browserOptions.disallowoverscroll) {
        if ([self.inAppBrowserViewController.webView respondsToSelector:@selector(scrollView)]) {
            ((UIScrollView*)[self.inAppBrowserViewController.webView scrollView]).bounces = NO;
        } else {
            for (id subview in self.inAppBrowserViewController.webView.subviews) {
                if ([[subview class] isSubclassOfClass:[UIScrollView class]]) {
                    ((UIScrollView*)subview).bounces = NO;
                }
            }
        }
    }

    // UIWebView options
    self.inAppBrowserViewController.webView.scalesPageToFit = browserOptions.enableviewportscale;
    self.inAppBrowserViewController.webView.mediaPlaybackRequiresUserAction = browserOptions.mediaplaybackrequiresuseraction;
    self.inAppBrowserViewController.webView.allowsInlineMediaPlayback = browserOptions.allowinlinemediaplayback;
    if (IsAtLeastiOSVersion(@"6.0")) {
        self.inAppBrowserViewController.webView.keyboardDisplayRequiresUserAction = browserOptions.keyboarddisplayrequiresuseraction;
        self.inAppBrowserViewController.webView.suppressesIncrementalRendering = browserOptions.suppressesincrementalrendering;
    }

    [self.inAppBrowserViewController navigateTo:url];
    if (!browserOptions.hidden) {
        [self show:nil];
    }
}

- (void)show:(CDVInvokedUrlCommand*)command
{
    if (self.inAppBrowserViewController == nil) {
        NSLog(@"Tried to show IAB after it was closed.");
        return;
    }
    if (_previousStatusBarStyle != -1) {
        NSLog(@"Tried to show IAB while already shown");
        return;
    }

    _previousStatusBarStyle = [UIApplication sharedApplication].statusBarStyle;

    CDVInAppBrowserNavigationController* nav = [[CDVInAppBrowserNavigationController alloc]
                                   initWithRootViewController:self.inAppBrowserViewController];
    nav.orientationDelegate = self.inAppBrowserViewController;
    nav.navigationBarHidden = YES;
    // Run later to avoid the "took a long time" log message.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.inAppBrowserViewController != nil) {
            [self.viewController presentViewController:nav animated:YES completion:nil];
        }
    });
}

- (void)openInCordovaWebView:(NSURL*)url withOptions:(NSString*)options
{
    if ([self.commandDelegate URLIsWhitelisted:url]) {
        NSURLRequest* request = [NSURLRequest requestWithURL:url];
        [self.webView loadRequest:request];
    } else { // this assumes the InAppBrowser can be excepted from the white-list
        [self openInInAppBrowser:url withOptions:options];
    }
}

- (void)openInSystem:(NSURL*)url
{
    if ([[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url];
    } else { // handle any custom schemes to plugins
        [[NSNotificationCenter defaultCenter] postNotification:[NSNotification notificationWithName:CDVPluginHandleOpenURLNotification object:url]];
    }
}

// This is a helper method for the inject{Script|Style}{Code|File} API calls, which
// provides a consistent method for injecting JavaScript code into the document.
//
// If a wrapper string is supplied, then the source string will be JSON-encoded (adding
// quotes) and wrapped using string formatting. (The wrapper string should have a single
// '%@' marker).
//
// If no wrapper is supplied, then the source string is executed directly.

- (void)injectDeferredObject:(NSString*)source withWrapper:(NSString*)jsWrapper
{
    if (!_injectedIframeBridge) {
        _injectedIframeBridge = YES;
        // Create an iframe bridge in the new document to communicate with the CDVInAppBrowserViewController
        [self.inAppBrowserViewController.webView stringByEvaluatingJavaScriptFromString:@"(function(d){var e = _cdvIframeBridge = d.createElement('iframe');e.style.display='none';d.body.appendChild(e);})(document)"];
    }

    if (jsWrapper != nil) {
        NSData* jsonData = [NSJSONSerialization dataWithJSONObject:@[source] options:0 error:nil];
        NSString* sourceArrayString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        if (sourceArrayString) {
            NSString* sourceString = [sourceArrayString substringWithRange:NSMakeRange(1, [sourceArrayString length] - 2)];
            NSString* jsToInject = [NSString stringWithFormat:jsWrapper, sourceString];
            [self.inAppBrowserViewController.webView stringByEvaluatingJavaScriptFromString:jsToInject];
        }
    } else {
        [self.inAppBrowserViewController.webView stringByEvaluatingJavaScriptFromString:source];
    }
}

- (void)injectScriptCode:(CDVInvokedUrlCommand*)command
{
    NSString* jsWrapper = nil;

    if ((command.callbackId != nil) && ![command.callbackId isEqualToString:@"INVALID"]) {
        jsWrapper = [NSString stringWithFormat:@"_cdvIframeBridge.src='gap-iab://%@/'+encodeURIComponent(JSON.stringify([eval(%%@)]));", command.callbackId];
    }
    [self injectDeferredObject:[command argumentAtIndex:0] withWrapper:jsWrapper];
}

- (void)injectScriptFile:(CDVInvokedUrlCommand*)command
{
    NSString* jsWrapper;

    if ((command.callbackId != nil) && ![command.callbackId isEqualToString:@"INVALID"]) {
        jsWrapper = [NSString stringWithFormat:@"(function(d) { var c = d.createElement('script'); c.src = %%@; c.onload = function() { _cdvIframeBridge.src='gap-iab://%@'; }; d.body.appendChild(c); })(document)", command.callbackId];
    } else {
        jsWrapper = @"(function(d) { var c = d.createElement('script'); c.src = %@; d.body.appendChild(c); })(document)";
    }
    [self injectDeferredObject:[command argumentAtIndex:0] withWrapper:jsWrapper];
}

- (void)injectStyleCode:(CDVInvokedUrlCommand*)command
{
    NSString* jsWrapper;

    if ((command.callbackId != nil) && ![command.callbackId isEqualToString:@"INVALID"]) {
        jsWrapper = [NSString stringWithFormat:@"(function(d) { var c = d.createElement('style'); c.innerHTML = %%@; c.onload = function() { _cdvIframeBridge.src='gap-iab://%@'; }; d.body.appendChild(c); })(document)", command.callbackId];
    } else {
        jsWrapper = @"(function(d) { var c = d.createElement('style'); c.innerHTML = %@; d.body.appendChild(c); })(document)";
    }
    [self injectDeferredObject:[command argumentAtIndex:0] withWrapper:jsWrapper];
}

- (void)injectStyleFile:(CDVInvokedUrlCommand*)command
{
    NSString* jsWrapper;

    if ((command.callbackId != nil) && ![command.callbackId isEqualToString:@"INVALID"]) {
        jsWrapper = [NSString stringWithFormat:@"(function(d) { var c = d.createElement('link'); c.rel='stylesheet'; c.type='text/css'; c.href = %%@; c.onload = function() { _cdvIframeBridge.src='gap-iab://%@'; }; d.body.appendChild(c); })(document)", command.callbackId];
    } else {
        jsWrapper = @"(function(d) { var c = d.createElement('link'); c.rel='stylesheet', c.type='text/css'; c.href = %@; d.body.appendChild(c); })(document)";
    }
    [self injectDeferredObject:[command argumentAtIndex:0] withWrapper:jsWrapper];
}

- (BOOL)isValidCallbackId:(NSString *)callbackId
{
    NSError *err = nil;
    // Initialize on first use
    if (self.callbackIdPattern == nil) {
        self.callbackIdPattern = [NSRegularExpression regularExpressionWithPattern:@"^InAppBrowser[0-9]{1,10}$" options:0 error:&err];
        if (err != nil) {
            // Couldn't initialize Regex; No is safer than Yes.
            return NO;
        }
    }
    if ([self.callbackIdPattern firstMatchInString:callbackId options:0 range:NSMakeRange(0, [callbackId length])]) {
        return YES;
    }
    return NO;
}

/**
 * The iframe bridge provided for the InAppBrowser is capable of executing any oustanding callback belonging
 * to the InAppBrowser plugin. Care has been taken that other callbacks cannot be triggered, and that no
 * other code execution is possible.
 *
 * To trigger the bridge, the iframe (or any other resource) should attempt to load a url of the form:
 *
 * gap-iab://<callbackId>/<arguments>
 *
 * where <callbackId> is the string id of the callback to trigger (something like "InAppBrowser0123456789")
 *
 * If present, the path component of the special gap-iab:// url is expected to be a URL-escaped JSON-encoded
 * value to pass to the callback. [NSURL path] should take care of the URL-unescaping, and a JSON_EXCEPTION
 * is returned if the JSON is invalid.
 */
- (BOOL)webView:(UIWebView*)theWebView shouldStartLoadWithRequest:(NSURLRequest*)request navigationType:(UIWebViewNavigationType)navigationType
{
    NSURL* url = request.URL;
    BOOL isTopLevelNavigation = [request.URL isEqual:[request mainDocumentURL]];

    // See if the url uses the 'gap-iab' protocol. If so, the host should be the id of a callback to execute,
    // and the path, if present, should be a JSON-encoded value to pass to the callback.
    if ([[url scheme] isEqualToString:@"gap-iab"]) {
        NSString* scriptCallbackId = [url host];
        CDVPluginResult* pluginResult = nil;

        if ([self isValidCallbackId:scriptCallbackId]) {
            NSString* scriptResult = [url path];
            NSError* __autoreleasing error = nil;

            // The message should be a JSON-encoded array of the result of the script which executed.
            if ((scriptResult != nil) && ([scriptResult length] > 1)) {
                scriptResult = [scriptResult substringFromIndex:1];
                NSData* decodedResult = [NSJSONSerialization JSONObjectWithData:[scriptResult dataUsingEncoding:NSUTF8StringEncoding] options:kNilOptions error:&error];
                if ((error == nil) && [decodedResult isKindOfClass:[NSArray class]]) {
                    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:(NSArray*)decodedResult];
                } else {
                    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_JSON_EXCEPTION];
                }
            } else {
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:@[]];
            }
            [self.commandDelegate sendPluginResult:pluginResult callbackId:scriptCallbackId];
            return NO;
        }
    } else if ((self.callbackId != nil) && isTopLevelNavigation) {
        // Send a loadstart event for each top-level navigation (includes redirects).
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                      messageAsDictionary:@{@"type":@"loadstart", @"url":[url absoluteString]}];
        [pluginResult setKeepCallback:[NSNumber numberWithBool:YES]];

        [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
    }

    return YES;
}

- (void)webViewDidStartLoad:(UIWebView*)theWebView
{
    _injectedIframeBridge = NO;
}

- (void)webViewDidFinishLoad:(UIWebView*)theWebView
{
    if (self.callbackId != nil) {
        // TODO: It would be more useful to return the URL the page is actually on (e.g. if it's been redirected).
        NSString* url = [self.inAppBrowserViewController.currentURL absoluteString];
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                      messageAsDictionary:@{@"type":@"loadstop", @"url":url}];
        [pluginResult setKeepCallback:[NSNumber numberWithBool:YES]];

        [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
    }
}

- (void)webView:(UIWebView*)theWebView didFailLoadWithError:(NSError*)error
{
    if (self.callbackId != nil) {
        NSString* url = [self.inAppBrowserViewController.currentURL absoluteString];
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                      messageAsDictionary:@{@"type":@"loaderror", @"url":url, @"code": [NSNumber numberWithInteger:error.code], @"message": error.localizedDescription}];
        [pluginResult setKeepCallback:[NSNumber numberWithBool:YES]];

        [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
    }
}

- (void)browserExit
{
    if (self.callbackId != nil) {
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                      messageAsDictionary:@{@"type":@"exit"}];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
        self.callbackId = nil;
    }
    // Set navigationDelegate to nil to ensure no callbacks are received from it.
    self.inAppBrowserViewController.navigationDelegate = nil;
    // Don't recycle the ViewController since it may be consuming a lot of memory.
    // Also - this is required for the PDF/User-Agent bug work-around.
    self.inAppBrowserViewController = nil;

    if (IsAtLeastiOSVersion(@"7.0")) {
        [[UIApplication sharedApplication] setStatusBarStyle:_previousStatusBarStyle];
    }

    _previousStatusBarStyle = -1; // this value was reset before reapplying it. caused statusbar to stay black on ios7
}

@end

#pragma mark CDVInAppBrowserViewController

@implementation CDVInAppBrowserViewController

@synthesize currentURL;

- (id)initWithUserAgent:(NSString*)userAgent prevUserAgent:(NSString*)prevUserAgent browserOptions: (CDVInAppBrowserOptions*) browserOptions
{
    self = [super init];
    if (self != nil) {
        _userAgent = userAgent;
        _prevUserAgent = prevUserAgent;
        _browserOptions = browserOptions;
        _webViewDelegate = [[CDVWebViewDelegate alloc] initWithDelegate:self];
        [self createViews];
    }

    return self;
}

- (void)createViews
{
    // We create the views in code for primarily for ease of upgrades and not requiring an external .xib to be included

    CGRect webViewBounds = self.view.bounds;
    BOOL toolbarIsAtBottom = ![_browserOptions.toolbarposition isEqualToString:kInAppBrowserToolbarBarPositionTop];
    webViewBounds.size.height -= _browserOptions.location ? FOOTER_HEIGHT : TOOLBAR_HEIGHT;
    self.webView = [[UIWebView alloc] initWithFrame:webViewBounds];

    self.webView.autoresizingMask = (UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight);

    [self.view addSubview:self.webView];
    [self.view sendSubviewToBack:self.webView];

    self.webView.delegate = _webViewDelegate;
    self.webView.backgroundColor = [UIColor colorWithWhite:0.909 alpha:1.0];

    self.webView.clearsContextBeforeDrawing = YES;
    self.webView.clipsToBounds = YES;
    self.webView.contentMode = UIViewContentModeScaleToFill;
    self.webView.multipleTouchEnabled = YES;
    self.webView.opaque = YES;
    self.webView.scalesPageToFit = NO;
    self.webView.userInteractionEnabled = YES;

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    self.spinner.alpha = 1.000;
    self.spinner.autoresizesSubviews = YES;
    self.spinner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin;
    self.spinner.clearsContextBeforeDrawing = NO;
    self.spinner.clipsToBounds = NO;
    self.spinner.contentMode = UIViewContentModeScaleToFill;
    self.spinner.frame = CGRectMake(454.0, 231.0, 20.0, 20.0);
    self.spinner.hidden = YES;
    self.spinner.hidesWhenStopped = YES;
    self.spinner.multipleTouchEnabled = NO;
    self.spinner.opaque = NO;
    self.spinner.userInteractionEnabled = NO;
    [self.spinner stopAnimating];

    // Close button
    // self.closeButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];
    self.closeButton = [[UIBarButtonItem alloc] initWithTitle:@"Stäng" style:UIBarButtonItemStylePlain target:self action:@selector(close)];
    [self.closeButton setTitleTextAttributes:[NSDictionary dictionaryWithObjectsAndKeys:[UIColor redColor], NSForegroundColorAttributeName, nil] forState:UIControlStateNormal];
    self.closeButton.enabled = YES;

    // Flexible space
    UIBarButtonItem* flexibleSpaceButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];

    // Fixed space
    UIBarButtonItem* fixedSpaceButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:nil action:nil];
    fixedSpaceButton.width = 20;

    float toolbarY = toolbarIsAtBottom ? self.view.bounds.size.height - TOOLBAR_HEIGHT : 0.0;
    CGRect toolbarFrame = CGRectMake(0.0, toolbarY, self.view.bounds.size.width, TOOLBAR_HEIGHT);

    self.toolbar = [[UIToolbar alloc] initWithFrame:toolbarFrame];
    self.toolbar.alpha = 1.000;
    self.toolbar.autoresizesSubviews = YES;
    self.toolbar.autoresizingMask = toolbarIsAtBottom ? (UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin) : UIViewAutoresizingFlexibleWidth;
    self.toolbar.barStyle = UIBarStyleBlack;
    self.toolbar.barTintColor = [UIColor colorWithWhite:0.909 alpha:1.0];
    self.toolbar.clearsContextBeforeDrawing = NO;
    self.toolbar.clipsToBounds = NO;
    self.toolbar.contentMode = UIViewContentModeScaleToFill;
    self.toolbar.hidden = NO;
    self.toolbar.multipleTouchEnabled = NO;
    self.toolbar.opaque = NO;
    self.toolbar.userInteractionEnabled = YES;

    // URL label
    CGFloat labelInset = 10.0;
    float locationBarY = toolbarIsAtBottom ? self.view.bounds.size.height - FOOTER_HEIGHT : self.view.bounds.size.height - LOCATIONBAR_HEIGHT;

    self.addressLabel = [[UILabel alloc] initWithFrame:CGRectMake(labelInset, locationBarY, self.view.bounds.size.width - labelInset, LOCATIONBAR_HEIGHT)];
    self.addressLabel.adjustsFontSizeToFitWidth = NO;
    self.addressLabel.alpha = 0.9;
    self.addressLabel.autoresizesSubviews = YES;
    self.addressLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin;
    self.addressLabel.backgroundColor = [UIColor colorWithWhite:0.5 alpha:0.75];
    self.addressLabel.baselineAdjustment = UIBaselineAdjustmentAlignCenters;
    self.addressLabel.clearsContextBeforeDrawing = YES;
    self.addressLabel.clipsToBounds = YES;
    self.addressLabel.contentMode = UIViewContentModeScaleToFill;
    self.addressLabel.enabled = YES;
    self.addressLabel.font = [UIFont systemFontOfSize:12];
    self.addressLabel.hidden = NO;
    self.addressLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    if ([self.addressLabel respondsToSelector:NSSelectorFromString(@"setMinimumScaleFactor:")]) {
        [self.addressLabel setValue:@(10.0/[UIFont labelFontSize]) forKey:@"minimumScaleFactor"];
    } else if ([self.addressLabel respondsToSelector:NSSelectorFromString(@"setMinimumFontSize:")]) {
        [self.addressLabel setValue:@(10.0) forKey:@"minimumFontSize"];
    }

    self.addressLabel.multipleTouchEnabled = NO;
    self.addressLabel.numberOfLines = 1;
    self.addressLabel.opaque = NO;
    self.addressLabel.shadowOffset = CGSizeMake(0.0, -1.0);
    self.addressLabel.text = NSLocalizedString(@"Laddar...", nil);
    self.addressLabel.textAlignment = NSTextAlignmentLeft;
    self.addressLabel.textColor = [UIColor colorWithWhite:0.909 alpha:1.0];
    self.addressLabel.userInteractionEnabled = NO;

    // w: 256, h: 448
    // ratio: 0.5714

    // Forward button
    NSString* frontArrowString = NSLocalizedString(@"►", nil); // create arrow from Unicode char
    self.forwardButton = [[UIBarButtonItem alloc] initWithTitle:frontArrowString style:UIBarButtonItemStylePlain target:self action:@selector(goForward:)];
    self.forwardButton.enabled = YES;
    self.forwardButton.imageInsets = UIEdgeInsetsZero;

    // Back button
    NSString *backArrowImageBase64String = @"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";
    NSData *backArrowImageData = [[NSData alloc] initWithBase64EncodedString:backArrowImageBase64String options:NSDataBase64DecodingIgnoreUnknownCharacters];
    UIImage *backArrowImage = [UIImage imageWithData:backArrowImageData];

    UIButton *backButton = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, 23, 40)];
    [backButton setBackgroundImage:backArrowImage forState:UIControlStateNormal];
    // self.backButton = [[UIBarButtonItem alloc] initWithImage:backArrowImage style:UIBarButtonItemStylePlain target:self action:@selector(close)];
    self.backButton = [[UIBarButtonItem alloc] initWithCustomView:backButton];
    self.backButton.enabled = YES;
    self.backButton.imageInsets = UIEdgeInsetsZero;

    [self.toolbar setItems:@[self.backButton, fixedSpaceButton, self.forwardButton, flexibleSpaceButton, self.closeButton]];

    self.view.backgroundColor = [UIColor blueColor];
    [self.view addSubview:self.toolbar];
    [self.view addSubview:self.addressLabel];
    [self.view addSubview:self.spinner];
}

- (void) setWebViewFrame : (CGRect) frame {
    NSLog(@"Setting the WebView's frame to %@", NSStringFromCGRect(frame));
    [self.webView setFrame:frame];
}

- (void)setCloseButtonTitle:(NSString*)title
{
    // the advantage of using UIBarButtonSystemItemDone is the system will localize it for you automatically
    // but, if you want to set this yourself, knock yourself out (we can't set the title for a system Done button, so we have to create a new one)
    self.closeButton = nil;
    self.closeButton = [[UIBarButtonItem alloc] initWithTitle:title style:UIBarButtonItemStyleBordered target:self action:@selector(close)];
    self.closeButton.enabled = YES;
    self.closeButton.tintColor = [UIColor colorWithRed:60.0 / 255.0 green:136.0 / 255.0 blue:230.0 / 255.0 alpha:1];

    NSMutableArray* items = [self.toolbar.items mutableCopy];
    [items replaceObjectAtIndex:0 withObject:self.closeButton];
    [self.toolbar setItems:items];
}

- (void)showLocationBar:(BOOL)show
{
    CGRect locationbarFrame = self.addressLabel.frame;

    BOOL toolbarVisible = !self.toolbar.hidden;

    // prevent double show/hide
    if (show == !(self.addressLabel.hidden)) {
        return;
    }

    if (show) {
        self.addressLabel.hidden = NO;

        if (toolbarVisible) {
            // toolBar at the bottom, leave as is
            // put locationBar on top of the toolBar

            CGRect webViewBounds = self.view.bounds;
            webViewBounds.size.height -= FOOTER_HEIGHT;
            [self setWebViewFrame:webViewBounds];

            locationbarFrame.origin.y = webViewBounds.size.height;
            self.addressLabel.frame = locationbarFrame;
        } else {
            // no toolBar, so put locationBar at the bottom

            CGRect webViewBounds = self.view.bounds;
            webViewBounds.size.height -= LOCATIONBAR_HEIGHT;
            [self setWebViewFrame:webViewBounds];

            locationbarFrame.origin.y = webViewBounds.size.height;
            self.addressLabel.frame = locationbarFrame;
        }
    } else {
        self.addressLabel.hidden = YES;

        if (toolbarVisible) {
            // locationBar is on top of toolBar, hide locationBar

            // webView take up whole height less toolBar height
            CGRect webViewBounds = self.view.bounds;
            webViewBounds.size.height -= TOOLBAR_HEIGHT;
            [self setWebViewFrame:webViewBounds];
        } else {
            // no toolBar, expand webView to screen dimensions
            [self setWebViewFrame:self.view.bounds];
        }
    }
}

- (void)showToolBar:(BOOL)show : (NSString *) toolbarPosition
{
    CGRect toolbarFrame = self.toolbar.frame;
    CGRect locationbarFrame = self.addressLabel.frame;

    BOOL locationbarVisible = !self.addressLabel.hidden;

    // prevent double show/hide
    if (show == !(self.toolbar.hidden)) {
        return;
    }

    if (show) {
        self.toolbar.hidden = NO;
        CGRect webViewBounds = self.view.bounds;

        if (locationbarVisible) {
            // locationBar at the bottom, move locationBar up
            // put toolBar at the bottom
            webViewBounds.size.height -= FOOTER_HEIGHT;
            locationbarFrame.origin.y = webViewBounds.size.height;
            self.addressLabel.frame = locationbarFrame;
            self.toolbar.frame = toolbarFrame;
        } else {
            // no locationBar, so put toolBar at the bottom
            CGRect webViewBounds = self.view.bounds;
            webViewBounds.size.height -= TOOLBAR_HEIGHT;
            self.toolbar.frame = toolbarFrame;
        }

        if ([toolbarPosition isEqualToString:kInAppBrowserToolbarBarPositionTop]) {
            toolbarFrame.origin.y = 0;
            webViewBounds.origin.y += toolbarFrame.size.height;
            [self setWebViewFrame:webViewBounds];
        } else {
            toolbarFrame.origin.y = (webViewBounds.size.height + LOCATIONBAR_HEIGHT);
        }
        [self setWebViewFrame:webViewBounds];

    } else {
        self.toolbar.hidden = YES;

        if (locationbarVisible) {
            // locationBar is on top of toolBar, hide toolBar
            // put locationBar at the bottom

            // webView take up whole height less locationBar height
            CGRect webViewBounds = self.view.bounds;
            webViewBounds.size.height -= LOCATIONBAR_HEIGHT;
            [self setWebViewFrame:webViewBounds];

            // move locationBar down
            locationbarFrame.origin.y = webViewBounds.size.height;
            self.addressLabel.frame = locationbarFrame;
        } else {
            // no locationBar, expand webView to screen dimensions
            [self setWebViewFrame:self.view.bounds];
        }
    }
}

- (void)viewDidLoad
{
    [super viewDidLoad];
}

- (void)viewDidUnload
{
    [self.webView loadHTMLString:nil baseURL:nil];
    [CDVUserAgentUtil releaseLock:&_userAgentLockToken];
    [super viewDidUnload];
}

- (UIStatusBarStyle)preferredStatusBarStyle
{
    return UIStatusBarStyleDefault;
}

- (void)close
{
    [CDVUserAgentUtil releaseLock:&_userAgentLockToken];
    self.currentURL = nil;

    if ((self.navigationDelegate != nil) && [self.navigationDelegate respondsToSelector:@selector(browserExit)]) {
        [self.navigationDelegate browserExit];
    }

    // Run later to avoid the "took a long time" log message.
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self respondsToSelector:@selector(presentingViewController)]) {
            [[self presentingViewController] dismissViewControllerAnimated:YES completion:nil];
        } else {
            [[self parentViewController] dismissViewControllerAnimated:YES completion:nil];
        }
    });
}

- (void)navigateTo:(NSURL*)url
{
    NSURLRequest* request = [NSURLRequest requestWithURL:url];

    if (_userAgentLockToken != 0) {
        [self.webView loadRequest:request];
    } else {
        [CDVUserAgentUtil acquireLock:^(NSInteger lockToken) {
            _userAgentLockToken = lockToken;
            [CDVUserAgentUtil setUserAgent:_userAgent lockToken:lockToken];
            [self.webView loadRequest:request];
        }];
    }
}

- (void)goBack:(id)sender
{
    [self.webView goBack];
}

- (void)goForward:(id)sender
{
    [self.webView goForward];
}

- (void)viewWillAppear:(BOOL)animated
{
    if (IsAtLeastiOSVersion(@"7.0")) {
        [[UIApplication sharedApplication] setStatusBarStyle:[self preferredStatusBarStyle]];
    }
    [self rePositionViews];

    [super viewWillAppear:animated];
}

//
// On iOS 7 the status bar is part of the view's dimensions, therefore it's height has to be taken into account.
// The height of it could be hardcoded as 20 pixels, but that would assume that the upcoming releases of iOS won't
// change that value.
//
- (float) getStatusBarOffset {
    CGRect statusBarFrame = [[UIApplication sharedApplication] statusBarFrame];
    float statusBarOffset = IsAtLeastiOSVersion(@"7.0") ? MIN(statusBarFrame.size.width, statusBarFrame.size.height) : 0.0;
    return statusBarOffset;
}

- (void) rePositionViews {
    if ([_browserOptions.toolbarposition isEqualToString:kInAppBrowserToolbarBarPositionTop]) {
        [self.webView setFrame:CGRectMake(self.webView.frame.origin.x, TOOLBAR_HEIGHT, self.webView.frame.size.width, self.webView.frame.size.height)];
        [self.toolbar setFrame:CGRectMake(self.toolbar.frame.origin.x, [self getStatusBarOffset], self.toolbar.frame.size.width, self.toolbar.frame.size.height)];
    }
}

#pragma mark UIWebViewDelegate

- (void)webViewDidStartLoad:(UIWebView*)theWebView
{
    // loading url, start spinner, update back/forward

    self.addressLabel.text = NSLocalizedString(@"Loading...", nil);
    self.backButton.enabled = theWebView.canGoBack;
    self.forwardButton.enabled = theWebView.canGoForward;

    [self.spinner startAnimating];

    return [self.navigationDelegate webViewDidStartLoad:theWebView];
}

- (BOOL)webView:(UIWebView*)theWebView shouldStartLoadWithRequest:(NSURLRequest*)request navigationType:(UIWebViewNavigationType)navigationType
{
    BOOL isTopLevelNavigation = [request.URL isEqual:[request mainDocumentURL]];

    if (isTopLevelNavigation) {
        self.currentURL = request.URL;
    }
    return [self.navigationDelegate webView:theWebView shouldStartLoadWithRequest:request navigationType:navigationType];
}

- (void)webViewDidFinishLoad:(UIWebView*)theWebView
{
    // update url, stop spinner, update back/forward

    self.addressLabel.text = [self.currentURL absoluteString];
    self.backButton.enabled = theWebView.canGoBack;
    self.forwardButton.enabled = theWebView.canGoForward;

    [self.spinner stopAnimating];

    // Work around a bug where the first time a PDF is opened, all UIWebViews
    // reload their User-Agent from NSUserDefaults.
    // This work-around makes the following assumptions:
    // 1. The app has only a single Cordova Webview. If not, then the app should
    //    take it upon themselves to load a PDF in the background as a part of
    //    their start-up flow.
    // 2. That the PDF does not require any additional network requests. We change
    //    the user-agent here back to that of the CDVViewController, so requests
    //    from it must pass through its white-list. This *does* break PDFs that
    //    contain links to other remote PDF/websites.
    // More info at https://issues.apache.org/jira/browse/CB-2225
    BOOL isPDF = [@"true" isEqualToString :[theWebView stringByEvaluatingJavaScriptFromString:@"document.body==null"]];
    if (isPDF) {
        [CDVUserAgentUtil setUserAgent:_prevUserAgent lockToken:_userAgentLockToken];
    }

    [self.navigationDelegate webViewDidFinishLoad:theWebView];
}

- (void)webView:(UIWebView*)theWebView didFailLoadWithError:(NSError*)error
{
    // log fail message, stop spinner, update back/forward
    NSLog(@"webView:didFailLoadWithError - %ld: %@", (long)error.code, [error localizedDescription]);

    self.backButton.enabled = theWebView.canGoBack;
    self.forwardButton.enabled = theWebView.canGoForward;
    [self.spinner stopAnimating];

    self.addressLabel.text = NSLocalizedString(@"Load Error", nil);

    [self.navigationDelegate webView:theWebView didFailLoadWithError:error];
}

#pragma mark CDVScreenOrientationDelegate

- (BOOL)shouldAutorotate
{
    if ((self.orientationDelegate != nil) && [self.orientationDelegate respondsToSelector:@selector(shouldAutorotate)]) {
        return [self.orientationDelegate shouldAutorotate];
    }
    return YES;
}

- (NSUInteger)supportedInterfaceOrientations
{
    if ((self.orientationDelegate != nil) && [self.orientationDelegate respondsToSelector:@selector(supportedInterfaceOrientations)]) {
        return [self.orientationDelegate supportedInterfaceOrientations];
    }

    return 1 << UIInterfaceOrientationPortrait;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    if ((self.orientationDelegate != nil) && [self.orientationDelegate respondsToSelector:@selector(shouldAutorotateToInterfaceOrientation:)]) {
        return [self.orientationDelegate shouldAutorotateToInterfaceOrientation:interfaceOrientation];
    }

    return YES;
}

@end

@implementation CDVInAppBrowserOptions

- (id)init
{
    if (self = [super init]) {
        // default values
        self.location = YES;
        self.toolbar = YES;
        self.closebuttoncaption = nil;
        self.toolbarposition = kInAppBrowserToolbarBarPositionBottom;
        self.clearcache = NO;
        self.clearsessioncache = NO;

        self.enableviewportscale = NO;
        self.mediaplaybackrequiresuseraction = NO;
        self.allowinlinemediaplayback = NO;
        self.keyboarddisplayrequiresuseraction = YES;
        self.suppressesincrementalrendering = NO;
        self.hidden = NO;
        self.disallowoverscroll = NO;
    }

    return self;
}

+ (CDVInAppBrowserOptions*)parseOptions:(NSString*)options
{
    CDVInAppBrowserOptions* obj = [[CDVInAppBrowserOptions alloc] init];

    // NOTE: this parsing does not handle quotes within values
    NSArray* pairs = [options componentsSeparatedByString:@","];

    // parse keys and values, set the properties
    for (NSString* pair in pairs) {
        NSArray* keyvalue = [pair componentsSeparatedByString:@"="];

        if ([keyvalue count] == 2) {
            NSString* key = [[keyvalue objectAtIndex:0] lowercaseString];
            NSString* value = [keyvalue objectAtIndex:1];
            NSString* value_lc = [value lowercaseString];

            BOOL isBoolean = [value_lc isEqualToString:@"yes"] || [value_lc isEqualToString:@"no"];
            NSNumberFormatter* numberFormatter = [[NSNumberFormatter alloc] init];
            [numberFormatter setAllowsFloats:YES];
            BOOL isNumber = [numberFormatter numberFromString:value_lc] != nil;

            // set the property according to the key name
            if ([obj respondsToSelector:NSSelectorFromString(key)]) {
                if (isNumber) {
                    [obj setValue:[numberFormatter numberFromString:value_lc] forKey:key];
                } else if (isBoolean) {
                    [obj setValue:[NSNumber numberWithBool:[value_lc isEqualToString:@"yes"]] forKey:key];
                } else {
                    [obj setValue:value forKey:key];
                }
            }
        }
    }

    return obj;
}

@end

@implementation CDVInAppBrowserNavigationController : UINavigationController

#pragma mark CDVScreenOrientationDelegate

- (BOOL)shouldAutorotate
{
    if ((self.orientationDelegate != nil) && [self.orientationDelegate respondsToSelector:@selector(shouldAutorotate)]) {
        return [self.orientationDelegate shouldAutorotate];
    }
    return YES;
}

- (NSUInteger)supportedInterfaceOrientations
{
    if ((self.orientationDelegate != nil) && [self.orientationDelegate respondsToSelector:@selector(supportedInterfaceOrientations)]) {
        return [self.orientationDelegate supportedInterfaceOrientations];
    }

    return 1 << UIInterfaceOrientationPortrait;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    if ((self.orientationDelegate != nil) && [self.orientationDelegate respondsToSelector:@selector(shouldAutorotateToInterfaceOrientation:)]) {
        return [self.orientationDelegate shouldAutorotateToInterfaceOrientation:interfaceOrientation];
    }

    return YES;
}


@end

