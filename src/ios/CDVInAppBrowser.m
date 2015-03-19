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
    // self.inAppBrowserViewController.modalPresentationStyle = UIModalPresentationCurrentContext;

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

    CGRect statusBarFrame = [[UIApplication sharedApplication] statusBarFrame];
    CGRect viewBounds     = self.view.bounds;
    CGRect webViewBounds  = self.view.bounds;

    // Layout parameters
    float closeButtonWidth = 44.0;
    float navButtonWidth   = 34.0;
    float pageInfoPadding  = 10.0;
    float dividerWidth     = 1.0;
    float shadowHeight     = 2.0;

    // Frames
    CGRect frameCloseButton   = CGRectMake(0.0, 0.0, closeButtonWidth, TOOLBAR_HEIGHT);
    CGRect frameDivider1      = CGRectMake(closeButtonWidth, 0.0, dividerWidth, TOOLBAR_HEIGHT);
    CGRect framePageInfo      = CGRectMake(closeButtonWidth + dividerWidth + pageInfoPadding, 0.0, viewBounds.size.width - (2 * navButtonWidth) - closeButtonWidth - (3 * dividerWidth) - (2 * pageInfoPadding), TOOLBAR_HEIGHT);
    CGRect frameDivider2      = CGRectMake(viewBounds.size.width - (2 * navButtonWidth) - (2 * dividerWidth), 0.0, dividerWidth, TOOLBAR_HEIGHT);
    CGRect frameNavBack       = CGRectMake(viewBounds.size.width - (2 * navButtonWidth) - dividerWidth, 0.0, navButtonWidth, TOOLBAR_HEIGHT);
    CGRect frameDivider3      = CGRectMake(viewBounds.size.width - navButtonWidth - dividerWidth, 0.0, dividerWidth, TOOLBAR_HEIGHT);
    CGRect frameNavForward    = CGRectMake(viewBounds.size.width - navButtonWidth, 0.0, navButtonWidth, TOOLBAR_HEIGHT);
    CGRect frameToolbarShadow = CGRectMake(0.0, TOOLBAR_HEIGHT - shadowHeight, viewBounds.size.width, shadowHeight);

    // Colors
    UIColor *mainBg          = [UIColor colorWithWhite:0.067 alpha:1.0];
    UIColor *toolbarBg       = [UIColor colorWithWhite:0.937 alpha:1.0];
    UIColor *toolbarShadowBg = [UIColor colorWithWhite:0.843 alpha:1.0];

    CGRect containerInitFrame = self.view.bounds;
    // containerInitFrame.origin.y = 100; // containerInitFrame.size.height;
    self.viewContainer = [[UIView alloc] initWithFrame:containerInitFrame];
    
    BOOL toolbarIsAtBottom = ![_browserOptions.toolbarposition isEqualToString:kInAppBrowserToolbarBarPositionTop];
    webViewBounds.size.height -= _browserOptions.location ? FOOTER_HEIGHT : TOOLBAR_HEIGHT;

    self.webView = [[UIWebView alloc] initWithFrame:webViewBounds];
    self.webView.autoresizingMask = (UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight);

    [self.viewContainer addSubview:self.webView];
    [self.viewContainer sendSubviewToBack:self.webView];

    // self.view.backgroundColor = [UIColor colorWithWhite:0.067 alpha:0.0];
    self.view.backgroundColor = mainBg;

    self.webView.delegate = _webViewDelegate;
    self.webView.backgroundColor = toolbarBg;

    self.webView.clearsContextBeforeDrawing = YES;
    self.webView.clipsToBounds              = YES;
    self.webView.contentMode                = UIViewContentModeScaleToFill;
    self.webView.multipleTouchEnabled       = YES;
    self.webView.opaque                     = YES;
    self.webView.scalesPageToFit            = NO;
    self.webView.userInteractionEnabled     = YES;

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    self.spinner.alpha                      = 1.0;
    self.spinner.autoresizesSubviews        = YES;
    self.spinner.autoresizingMask           = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin;
    self.spinner.clearsContextBeforeDrawing = NO;
    self.spinner.clipsToBounds              = NO;
    self.spinner.contentMode                = UIViewContentModeScaleToFill;
    self.spinner.frame                      = CGRectMake(454.0, 231.0, 20.0, 20.0);
    self.spinner.hidden                     = YES;
    self.spinner.hidesWhenStopped           = YES;
    self.spinner.multipleTouchEnabled       = NO;
    self.spinner.opaque                     = NO;
    self.spinner.userInteractionEnabled     = NO;
    [self.spinner stopAnimating];

    // URL label
    CGFloat labelInset = 10.0;
    float locationBarY = toolbarIsAtBottom ? self.view.bounds.size.height - FOOTER_HEIGHT : self.view.bounds.size.height - LOCATIONBAR_HEIGHT;

    self.addressLabel = [[UILabel alloc] initWithFrame:CGRectMake(labelInset, locationBarY, self.view.bounds.size.width - labelInset, LOCATIONBAR_HEIGHT)];
    self.addressLabel.adjustsFontSizeToFitWidth  = NO;
    self.addressLabel.alpha                      = 1.0;
    self.addressLabel.autoresizesSubviews        = YES;
    self.addressLabel.autoresizingMask           = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin;
    self.addressLabel.backgroundColor            = [UIColor clearColor];
    self.addressLabel.baselineAdjustment         = UIBaselineAdjustmentAlignCenters;
    self.addressLabel.clearsContextBeforeDrawing = YES;
    self.addressLabel.clipsToBounds              = YES;
    self.addressLabel.contentMode                = UIViewContentModeScaleToFill;
    self.addressLabel.enabled                    = YES;
    self.addressLabel.font                       = [UIFont systemFontOfSize:12];
    self.addressLabel.hidden                     = NO;
    self.addressLabel.lineBreakMode              = NSLineBreakByTruncatingTail;

    if ([self.addressLabel respondsToSelector:NSSelectorFromString(@"setMinimumScaleFactor:")]) {
        [self.addressLabel setValue:@(10.0/[UIFont labelFontSize]) forKey:@"minimumScaleFactor"];
    } else if ([self.addressLabel respondsToSelector:NSSelectorFromString(@"setMinimumFontSize:")]) {
        [self.addressLabel setValue:@(10.0) forKey:@"minimumFontSize"];
    }

    self.addressLabel.multipleTouchEnabled   = NO;
    self.addressLabel.numberOfLines          = 1;
    self.addressLabel.opaque                 = NO;
    self.addressLabel.shadowOffset           = CGSizeMake(0.0, -1.0);
    self.addressLabel.text                   = NSLocalizedString(@"Laddar...", nil);
    self.addressLabel.textAlignment          = NSTextAlignmentLeft;
    self.addressLabel.textColor              = [UIColor colorWithWhite:0.25 alpha:1.0];
    self.addressLabel.userInteractionEnabled = NO;

    // w: 256, h: 448
    // ratio: 0.5714

    // small arrows: 9 x 16

    UIEdgeInsets buttonInsets = UIEdgeInsetsMake(14.0, 12.0, 14.0, 12.0);

    // Close button
    self.closeButton = [[UIButton alloc] initWithFrame:frameCloseButton];
    NSString *closeButtonBase64String = @"iVBORw0KGgoAAAANSUhEUgAAAFgAAABYCAYAAABxlTA0AAAAAXNSR0IArs4c6QAAAuFJREFUeAHt3VFypCAQBuBsLrU5Wt7ikTcnyNKT/BNlEAEZpLt/qpgWREq/ocAHJnl5Saf3UP2WPsXahMDfUCdmRWkJrb5C/gxZLmTKC4jRv5DFbAk5m5ZwVhoiEznLdRuAwIWZGCbTEmrRaB2JnORK4sJNLDdpCSWcTEUib7iyuPD7wCUyOaMyFwWZC9/3uhRPC3tut4VP0ARvr9G63vtIXi9oa5fU8WZAEjmMsIPUjIt+pQOOZGhsYy2utE8mIj+ydMNF10SGRN2CVrU+EfmJuPj+PCN3nxaAGkePyMNwge0JeTiuJ+TLcD0gX45rGXkaXIvI0+FaQp4W1wLy9LiakdXgakRWh6sJWS2uBmT1uDMjm8GdEdkc7kzIZnFnQDaPeyWyG9wrkN3hjkR2izsC2T1uC7Ls/xK4o0TcSEhASncQHSETN8JFsQcycaG5E88gE3cHNa5uQSZurHhQrkUu3fxctVfs4B7Vn64ZlanNznHd0eKoHqzlAXohEzejfxaZuBlcnGpFJi4EC2It8rS4rwUPq6HJHw03Ocs91o5evEHwtazgG2zFJfIAXCJnkM+OXOAicrpYYdfgytuCZEDmoiC7/211La60lyx4OVyccz2SW3CD6y0RGRI78QwuuiQyJKLYAxddEhkSP7EnLrom8hNxiTwA1z3yM6YFoMbR3XQxEhfYbpCvwHWDfCWueeQZcM0iz4RrDnlGXDPIM+OqR9aAqxZZE646ZI24apA1406PbAG3BXnI7iFLuNMhW8SdBtky7uXIHnDXyKX7LrrMyZ5whyN7xB2G7Bn36cjEBXHdX8EumpOJ+4uLo24m3TrCnRmKp21Od2AIc+9Rmo2aL9y7E8P1TVbyD42wnzYXiyZxw7h4tBpksb2lJXwS99ui5LMEWUw36SOUUsgcuRumeyGHvNxbRQcxMnEjoKiYQl6iNg9FIBP3gSZZsUZeki0SlTI5y4VMZQJidV/Q1pf8B+aS7SrsrkmwAAAAAElFTkSuQmCC";
    UIImage *closeButtonImage = [UIImage imageWithData:[[NSData alloc] initWithBase64EncodedString:closeButtonBase64String options:NSDataBase64DecodingIgnoreUnknownCharacters]];
    [self.closeButton setContentEdgeInsets:UIEdgeInsetsMake(14.0, 14.0, 14.0, 14.0)];
    [self.closeButton setImage:closeButtonImage forState:UIControlStateNormal];
    // [self.closeButton setBackgroundColor:[UIColor redColor]];
    [self.closeButton addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];

    // Back button
    NSString *backArrowImageBase64String = @"iVBORw0KGgoAAAANSUhEUgAAADIAAABYCAYAAAC3UKSNAAAAAXNSR0IArs4c6QAAAU5JREFUeAHtm0sKwlAMRYu7cSO6ECd+Fq47cKivgwuF1sY3MNzUI5SgEZJ7jg+k0GGo9Tq2dS+1Vp5vO4Z4tuvVrtu8XeOTaYgxSMkwSyHKhVkLUSbMNyEU5uR6QnpC3FuIvWMQQrhY+TsTjy2cCUL88vz0nAlMYCIgwM8pAJTWxkQa6mAQJgJAaW1MpKEOBmEiAJTWxkQa6mDQofV1G1O3Zj5V27/ihAgsp7UxkYY6GISJAFBaGxNpqINBmAgApbUxkYY6GISJAFBaexMmdmm4kgZtwopYEUYk3Cpm3IxoH8yIhFvFjJsR7YMZkXCrmHEzon0wIxJuFTNuRrQPZkTCrWLGzYj2wYxIuFXMuBnRPpgRCbeKGTcj2gczIuFWMeNmRPtgRiTcKmbcjGifHjO2Dx33hLnqy+51zUyZEIK8FKZciKUwZUNMw5z1ZlrfQaqRJsc1vK8AAAAASUVORK5CYII=";
    NSData *backArrowImageData = [[NSData alloc] initWithBase64EncodedString:backArrowImageBase64String options:NSDataBase64DecodingIgnoreUnknownCharacters];
    UIImage *backArrowImage = [UIImage imageWithData:backArrowImageData];
    self.backButton = [[UIButton alloc] initWithFrame:frameNavBack];
    [self.backButton setContentEdgeInsets:buttonInsets];
    [self.backButton setImage:backArrowImage forState:UIControlStateNormal];
    // [self.backButton setBackgroundColor:[UIColor yellowColor]];
    [self.backButton addTarget:self action:@selector(goBack:) forControlEvents:UIControlEventTouchUpInside];
    [self.backButton setEnabled:NO];

    // Forward button
    NSString *forwArrowImageBase64String = @"iVBORw0KGgoAAAANSUhEUgAAADIAAABYCAYAAAC3UKSNAAAAAXNSR0IArs4c6QAAAYNJREFUeAHtnEFOAzEMRYEegVPAQehB2EA5M/vegCU4SJasEha2HOln9EaKEqVj9///pouOOj3dzY9323608Tl/eY/dD5P5bePLxnkPyX9VXmxrmPCxpZlbE1ua+c/EVmZew6Xkwmez/GX2bEaumLEE1A7IqBFxPZDxJNRmyKgRcT2Q8STUZsioEXE9kPEk1GbIqBFxPZDxJNRmyKgRcT2Q8STU5iyZFzUDUc+hzDyZs8x9M2kymInXqdIaMko0ohbIxDSU1pBRohG1QCamobSGjBKNqCVN5iFWC63vhbSUpRziOwwmyvybCyHRHGi5HSTK0TUXQqI50HI7SJSjay6ERHOg5XaQKEfXXAiJ5kDL7SBRjq65EBLNgZbbpW/blN9pYSEmFoabag2JVFwLT4bEwnBTrSGRimvhyZBYGG6qNSRScS08GRILw021PgSJ4Tjz0LH07w2HGf9XgdlT02NvPDktb2IYGcfFxszIViZ+nUzMbGni1szWJtzMmy22+UwM0T/QxZICjR2eTQAAAABJRU5ErkJggg==";
    NSData *forwArrowImageData = [[NSData alloc] initWithBase64EncodedString:forwArrowImageBase64String options:NSDataBase64DecodingIgnoreUnknownCharacters];
    UIImage *forwArrowImage = [UIImage imageWithData:forwArrowImageData];
    self.forwardButton = [[UIButton alloc] initWithFrame:frameNavForward];
    [self.forwardButton setContentEdgeInsets:buttonInsets];
    [self.forwardButton setImage:forwArrowImage forState:UIControlStateNormal];
    // [self.forwardButton setBackgroundColor:[UIColor orangeColor]];
    [self.forwardButton addTarget:self action:@selector(goForward:) forControlEvents:UIControlEventTouchUpInside];
    [self.forwardButton setEnabled:NO];

    // self.forwardButton = [[UIBarButtonItem alloc] initWithCustomView:forwButton];
    // self.forwardButton.enabled = YES;
    // self.forwardButton.imageInsets = UIEdgeInsetsZero;
    
    // self.backButton = [[UIBarButtonItem alloc] initWithCustomView:backButton];
    // self.backButton.enabled = YES;
    // self.backButton.imageInsets = UIEdgeInsetsZero;

    // Page title + url
    UIView *pageInfoView = [[UIView alloc] initWithFrame:framePageInfo];
    // pageInfoView.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    self.pageTitleLabel  = [[UILabel alloc] initWithFrame:CGRectMake(0.0, 8.0, pageInfoView.bounds.size.width, 16.0)];
    self.pageTitleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.pageTitleLabel.text             = @"Laddar...";
    self.pageTitleLabel.font             = [UIFont boldSystemFontOfSize:13];
    self.pageTitleLabel.textColor        = [UIColor colorWithWhite:0.267 alpha:1.0];

    self.pageUrlLabel  = [[UILabel alloc] initWithFrame:CGRectMake(0.0, 26.0, pageInfoView.bounds.size.width, 10.0)];
    self.pageUrlLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.pageUrlLabel.text             = @"";
    self.pageUrlLabel.font             = [UIFont systemFontOfSize:10];
    self.pageUrlLabel.textColor        = [UIColor colorWithWhite:0.7 alpha:1.0];

    [pageInfoView addSubview:self.pageTitleLabel];
    [pageInfoView addSubview:self.pageUrlLabel];

    self.pageTitle = pageInfoView; // [[UIBarButtonItem alloc] initWithCustomView:pageInfoView];

    // Dividers
    UIView *divider1 = [[UIView alloc] initWithFrame:frameDivider1];
    UIView *divider2 = [[UIView alloc] initWithFrame:frameDivider2];
    UIView *divider3 = [[UIView alloc] initWithFrame:frameDivider3];
    divider1.backgroundColor = toolbarShadowBg;
    divider2.backgroundColor = toolbarShadowBg;
    divider3.backgroundColor = toolbarShadowBg;

    // Shadow
    UIView *toolbarShadow = [[UIView alloc] initWithFrame:frameToolbarShadow];
    toolbarShadow.backgroundColor = toolbarShadowBg;

    // Toolbar
    float toolbarY      = toolbarIsAtBottom ? self.view.bounds.size.height - TOOLBAR_HEIGHT : 20.0;
    CGRect toolbarFrame = CGRectMake(0.0, toolbarY, self.view.bounds.size.width, TOOLBAR_HEIGHT);

    self.toolbarPlain = [[UIView alloc] initWithFrame:toolbarFrame];
    self.toolbarPlain.backgroundColor = toolbarBg;
    [self.toolbarPlain addSubview:self.closeButton];
    [self.toolbarPlain addSubview:divider1];
    [self.toolbarPlain addSubview:self.pageTitle];
    [self.toolbarPlain addSubview:divider2];
    [self.toolbarPlain addSubview:self.backButton];
    [self.toolbarPlain addSubview:divider3];
    [self.toolbarPlain addSubview:self.forwardButton];
    [self.toolbarPlain addSubview:toolbarShadow];

    // self.addressLabel.text = [NSString stringWithFormat:@"w: %f, h: %f", statusBarFrame.size.width, statusBarFrame.size.height];

    // self.toolbar = [[UIToolbar alloc] initWithFrame:toolbarFrame];
    // self.toolbar.alpha = 1.000;
    // self.toolbar.autoresizesSubviews = YES;
    // self.toolbar.autoresizingMask = toolbarIsAtBottom ? (UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin) : UIViewAutoresizingFlexibleWidth;
    // self.toolbar.barStyle = UIBarStyleBlack;
    // self.toolbar.barTintColor = [UIColor colorWithWhite:0.909 alpha:1.0];
    // self.toolbar.clearsContextBeforeDrawing = NO;
    // self.toolbar.clipsToBounds = NO;
    // self.toolbar.contentMode = UIViewContentModeScaleToFill;
    // self.toolbar.hidden = NO;
    // self.toolbar.multipleTouchEnabled = NO;
    // self.toolbar.opaque = NO;
    // self.toolbar.userInteractionEnabled = YES;

    // // Flexible space
    // UIBarButtonItem* flexibleSpaceButtonLeft = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    // UIBarButtonItem* flexibleSpaceButtonRight = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];

    // // Fixed space
    // UIBarButtonItem* fixedSpaceButtonLeft = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:nil action:nil];
    // fixedSpaceButtonLeft.width = -16.0;
    // UIBarButtonItem* fixedSpaceButtonRight = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:nil action:nil];
    // fixedSpaceButtonRight.width = -16.0;

    // // Dividers
    // UIView *divider1View = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 1.0, TOOLBAR_HEIGHT)];
    // [divider1View setBackgroundColor:[UIColor blackColor]];
    // UIBarButtonItem *divider1 = [[UIBarButtonItem alloc] initWithCustomView:divider1View];

    // UIView *divider2View = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 1.0, TOOLBAR_HEIGHT)];
    // [divider2View setBackgroundColor:[UIColor blackColor]];
    // UIBarButtonItem *divider2 = [[UIBarButtonItem alloc] initWithCustomView:divider2View];

    // UIView *divider3View = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 1.0, TOOLBAR_HEIGHT)];
    // [divider3View setBackgroundColor:[UIColor blackColor]];
    // UIBarButtonItem *divider3 = [[UIBarButtonItem alloc] initWithCustomView:divider3View];

    // UIBarButtonItem *noSpace1 = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:nil action:nil];
    // UIBarButtonItem *noSpace2 = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:nil action:nil];
    // UIBarButtonItem *noSpace3 = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:nil action:nil];
    // UIBarButtonItem *noSpace4 = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:nil action:nil];
    // UIBarButtonItem *noSpace5 = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:nil action:nil];
    // UIBarButtonItem *noSpace6 = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:nil action:nil];
    // noSpace1.width = -10.0;
    // noSpace2.width = -10.0;
    // noSpace3.width = -10.0;
    // noSpace4.width = -10.0;
    // noSpace5.width = -10.0;
    // noSpace6.width = -10.0;

    // UIView *aSpace1View = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 10.0, TOOLBAR_HEIGHT)];
    // [aSpace1View setBackgroundColor:[UIColor blueColor]];
    // UIBarButtonItem *aSpace1 = [[UIBarButtonItem alloc] initWithCustomView:aSpace1View];

    // [self.toolbar setItems:@[fixedSpaceButtonLeft, self.closeButton, noSpace1, divider1, self.pageTitle, flexibleSpaceButtonRight, aSpace1, divider2, noSpace4, self.backButton, noSpace5, divider3, noSpace6, self.forwardButton, fixedSpaceButtonRight]];

    // self.view.backgroundColor = [UIColor colorWithWhite:0.909 alpha:1.0];
    // [self.viewContainer addSubview:self.toolbar];
    [self.viewContainer addSubview:self.toolbarPlain];
    [self.viewContainer addSubview:self.addressLabel];
    [self.viewContainer addSubview:self.spinner];

    [self.view addSubview:self.viewContainer];
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

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(rePositionViews)
                                                 name:UIApplicationDidChangeStatusBarFrameNotification
                                               object:nil];

    [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleLightContent];
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
    NSLog(@"getStatusBarOffset: %f", statusBarOffset);
    return statusBarOffset;
}

- (void) rePositionViews {
    NSLog(@"reposition views");

    if ([_browserOptions.toolbarposition isEqualToString:kInAppBrowserToolbarBarPositionTop]) {
        [self.webView setFrame:CGRectMake(self.webView.frame.origin.x, TOOLBAR_HEIGHT, self.webView.frame.size.width, self.view.frame.size.height - 20.0)];
        [self.toolbar setFrame:CGRectMake(self.toolbar.frame.origin.x, 20.0, self.toolbar.frame.size.width, self.toolbar.frame.size.height)];
    }
}

#pragma mark UIWebViewDelegate

- (void)webViewDidStartLoad:(UIWebView*)theWebView
{
    // loading url, start spinner, update back/forward

    // self.addressLabel.text = NSLocalizedString(@"Loading...", nil);
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

        // Update URL label
        self.pageTitleLabel.text = @"Laddar...";
        self.pageUrlLabel.text   = request.URL.absoluteString;
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

    self.pageTitleLabel.text = [theWebView stringByEvaluatingJavaScriptFromString:@"document.title"];
    self.pageUrlLabel.text   = theWebView.request.URL.absoluteString;

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

- (void)dismissViewControllerAnimated:(BOOL)flag completion:(void (^)(void))completion
{
    if ( self.presentedViewController)
    {
        [super dismissViewControllerAnimated:flag completion:completion];
    }
}


@end
