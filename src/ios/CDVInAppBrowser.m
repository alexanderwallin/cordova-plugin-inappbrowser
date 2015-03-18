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
    CGRect viewBounds = self.view.bounds;
    CGRect webViewBounds = self.view.bounds;

    UIEdgeInsets buttonInsets = UIEdgeInsetsMake(14.0, 4.0, 14.0, 4.0);

    // viewBounds.origin.y = 150.0;
    // viewBounds.size.width = 200.0;
    // viewBounds.size.height = 300.0;
    // [self.view setFrame:viewBounds];

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
    self.view.backgroundColor = [UIColor colorWithWhite:0.909 alpha:1.0];

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
    UIButton *closeButton = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, 44, 44)];
    NSString *closeButtonBase64String = @"iVBORw0KGgoAAAANSUhEUgAAAFgAAABYCAYAAABxlTA0AAAAAXNSR0IArs4c6QAAAuFJREFUeAHt3VFypCAQBuBsLrU5Wt7ikTcnyNKT/BNlEAEZpLt/qpgWREq/ocAHJnl5Saf3UP2WPsXahMDfUCdmRWkJrb5C/gxZLmTKC4jRv5DFbAk5m5ZwVhoiEznLdRuAwIWZGCbTEmrRaB2JnORK4sJNLDdpCSWcTEUib7iyuPD7wCUyOaMyFwWZC9/3uhRPC3tut4VP0ARvr9G63vtIXi9oa5fU8WZAEjmMsIPUjIt+pQOOZGhsYy2utE8mIj+ydMNF10SGRN2CVrU+EfmJuPj+PCN3nxaAGkePyMNwge0JeTiuJ+TLcD0gX45rGXkaXIvI0+FaQp4W1wLy9LiakdXgakRWh6sJWS2uBmT1uDMjm8GdEdkc7kzIZnFnQDaPeyWyG9wrkN3hjkR2izsC2T1uC7Ls/xK4o0TcSEhASncQHSETN8JFsQcycaG5E88gE3cHNa5uQSZurHhQrkUu3fxctVfs4B7Vn64ZlanNznHd0eKoHqzlAXohEzejfxaZuBlcnGpFJi4EC2It8rS4rwUPq6HJHw03Ocs91o5evEHwtazgG2zFJfIAXCJnkM+OXOAicrpYYdfgytuCZEDmoiC7/211La60lyx4OVyccz2SW3CD6y0RGRI78QwuuiQyJKLYAxddEhkSP7EnLrom8hNxiTwA1z3yM6YFoMbR3XQxEhfYbpCvwHWDfCWueeQZcM0iz4RrDnlGXDPIM+OqR9aAqxZZE646ZI24apA1406PbAG3BXnI7iFLuNMhW8SdBtky7uXIHnDXyKX7LrrMyZ5whyN7xB2G7Bn36cjEBXHdX8EumpOJ+4uLo24m3TrCnRmKp21Od2AIc+9Rmo2aL9y7E8P1TVbyD42wnzYXiyZxw7h4tBpksb2lJXwS99ui5LMEWUw36SOUUsgcuRumeyGHvNxbRQcxMnEjoKiYQl6iNg9FIBP3gSZZsUZeki0SlTI5y4VMZQJidV/Q1pf8B+aS7SrsrkmwAAAAAElFTkSuQmCC";
    UIImage *closeButtonImage = [UIImage imageWithData:[[NSData alloc] initWithBase64EncodedString:closeButtonBase64String options:NSDataBase64DecodingIgnoreUnknownCharacters]];
    [closeButton setContentEdgeInsets:UIEdgeInsetsMake(14.0, 14.0, 14.0, 14.0)];
    [closeButton setImage:closeButtonImage forState:UIControlStateNormal];
    [closeButton setBackgroundColor:[UIColor redColor]];
    [closeButton addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    self.closeButton = [[UIBarButtonItem alloc] initWithCustomView:closeButton];
    self.closeButton.enabled = YES;

    // URL label
    CGFloat labelInset = 10.0;
    float locationBarY = toolbarIsAtBottom ? self.view.bounds.size.height - FOOTER_HEIGHT : self.view.bounds.size.height - LOCATIONBAR_HEIGHT;

    self.addressLabel = [[UILabel alloc] initWithFrame:CGRectMake(labelInset, locationBarY, self.view.bounds.size.width - labelInset, LOCATIONBAR_HEIGHT)];
    self.addressLabel.adjustsFontSizeToFitWidth = NO;
    self.addressLabel.alpha = 1.0;
    self.addressLabel.autoresizesSubviews = YES;
    self.addressLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin;
    self.addressLabel.backgroundColor = [UIColor clearColor];
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
    self.addressLabel.textColor = [UIColor colorWithWhite:0.25 alpha:1.0];
    self.addressLabel.userInteractionEnabled = NO;

    // w: 256, h: 448
    // ratio: 0.5714

    // small arrows: 9 x 16

    // Forward button
    NSString *forwArrowImageBase64String = @"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";
    NSData *forwArrowImageData = [[NSData alloc] initWithBase64EncodedString:forwArrowImageBase64String options:NSDataBase64DecodingIgnoreUnknownCharacters];
    UIImage *forwArrowImage = [UIImage imageWithData:forwArrowImageData];
    UIButton *forwButton = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, 17, 44)];
    [forwButton setContentEdgeInsets:buttonInsets];
    [forwButton setImage:forwArrowImage forState:UIControlStateNormal];
    [forwButton setBackgroundColor:[UIColor orangeColor]];
    [forwButton addTarget:self action:@selector(goForward:) forControlEvents:UIControlEventTouchUpInside];

    self.forwardButton = [[UIBarButtonItem alloc] initWithCustomView:forwButton];
    self.forwardButton.enabled = YES;
    self.forwardButton.imageInsets = UIEdgeInsetsZero;

    // Back button
    NSString *backArrowImageBase64String = @"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";
    NSData *backArrowImageData = [[NSData alloc] initWithBase64EncodedString:backArrowImageBase64String options:NSDataBase64DecodingIgnoreUnknownCharacters];
    UIImage *backArrowImage = [UIImage imageWithData:backArrowImageData];
    UIButton *backButton = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, 17, 44)];
    [backButton setContentEdgeInsets:buttonInsets];
    [backButton setImage:backArrowImage forState:UIControlStateNormal];
    [backButton addTarget:self action:@selector(goBack:) forControlEvents:UIControlEventTouchUpInside];
    
    self.backButton = [[UIBarButtonItem alloc] initWithCustomView:backButton];
    self.backButton.enabled = YES;
    self.backButton.imageInsets = UIEdgeInsetsZero;

    // Page title + url
    UIView *pageInfoView = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 200.0, TOOLBAR_HEIGHT)];
    pageInfoView.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    self.pageTitleLabel  = [[UILabel alloc] initWithFrame:CGRectMake(0.0, 10.0, pageInfoView.bounds.size.width, 16.0)];
    self.pageTitleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.pageTitleLabel.text      = @"Laddar...";
    self.pageTitleLabel.font      = [UIFont boldSystemFontOfSize:13];
    self.pageTitleLabel.textColor = [UIColor colorWithWhite:0.267 alpha:1.0];

    self.pageUrlLabel  = [[UILabel alloc] initWithFrame:CGRectMake(0.0, 26.0, pageInfoView.bounds.size.width, 10.0)];
    self.pageUrlLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.pageUrlLabel.text      = @"http://www.example.com";
    self.pageUrlLabel.font      = [UIFont systemFontOfSize:10];
    self.pageUrlLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];

    [pageInfoView addSubview:self.pageTitleLabel];
    [pageInfoView addSubview:self.pageUrlLabel];

    self.pageTitle = [[UIBarButtonItem alloc] initWithCustomView:pageInfoView];

    // Toolbar
    float toolbarY = toolbarIsAtBottom ? self.view.bounds.size.height - TOOLBAR_HEIGHT : 0.0;
    CGRect toolbarFrame = CGRectMake(0.0, toolbarY, self.view.bounds.size.width, TOOLBAR_HEIGHT);

    // self.addressLabel.text = [NSString stringWithFormat:@"w: %f, h: %f", statusBarFrame.size.width, statusBarFrame.size.height];

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

    // Flexible space
    UIBarButtonItem* flexibleSpaceButtonLeft = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    UIBarButtonItem* flexibleSpaceButtonRight = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];

    // Fixed space
    UIBarButtonItem* fixedSpaceButtonLeft = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:nil action:nil];
    fixedSpaceButtonLeft.width = -20.0;
    UIBarButtonItem* fixedSpaceButtonRight = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:nil action:nil];
    fixedSpaceButtonRight.width = -40.0;

    [self.toolbar setItems:@[fixedSpaceButtonLeft, self.closeButton, self.pageTitle, self.backButton, self.forwardButton, fixedSpaceButtonRight]];

    // self.view.backgroundColor = [UIColor colorWithWhite:0.909 alpha:1.0];
    [self.viewContainer addSubview:self.toolbar];
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
