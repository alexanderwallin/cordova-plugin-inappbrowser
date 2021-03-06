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
package org.apache.cordova.inappbrowser;

import android.annotation.SuppressLint;
import org.apache.cordova.inappbrowser.InAppBrowserDialog;
import android.content.Context;
import android.content.Intent;
import android.provider.Browser;
import android.content.res.Resources;
import android.graphics.Bitmap;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.ShapeDrawable;
import android.graphics.drawable.shapes.RectShape;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.text.InputType;
import android.text.TextUtils;
import android.util.Log;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.View;
import android.view.Window;
import android.view.WindowManager;
import android.view.WindowManager.LayoutParams;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputMethodManager;
import android.webkit.CookieManager;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Button;
import android.widget.ImageButton;
import android.widget.ImageView;
import android.widget.TextView;
import android.widget.LinearLayout;
import android.widget.RelativeLayout;

import org.apache.cordova.CallbackContext;
import org.apache.cordova.Config;
import org.apache.cordova.CordovaArgs;
import org.apache.cordova.CordovaPlugin;
import org.apache.cordova.CordovaWebView;
import org.apache.cordova.LOG;
import org.apache.cordova.PluginManager;
import org.apache.cordova.PluginResult;
import org.json.JSONException;
import org.json.JSONObject;

import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.util.HashMap;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.StringTokenizer;

@SuppressLint("SetJavaScriptEnabled")
public class InAppBrowser extends CordovaPlugin {

    private static final String NULL = "null";
    protected static final String LOG_TAG = "InAppBrowser";
    private static final String SELF = "_self";
    private static final String SYSTEM = "_system";
    private static final String LEAVE_IAB_REGEX = "leaveiab";
    private static final String LOADING_CAPTION = "loadingcaption";
    // private static final String BLANK = "_blank";
    private static final String EXIT_EVENT = "exit";
    private static final String LOCATION = "location";
    private static final String TOOLBAR = "toolbar";
    private static final String ZOOM = "zoom";
    private static final String HIDDEN = "hidden";
    private static final String LOAD_START_EVENT = "loadstart";
    private static final String LOAD_STOP_EVENT = "loadstop";
    private static final String LOAD_ERROR_EVENT = "loaderror";
    private static final String CLEAR_ALL_CACHE = "clearcache";
    private static final String CLEAR_SESSION_CACHE = "clearsessioncache";
    private static final String HARDWARE_BACK_BUTTON = "hardwareback";

    private InAppBrowserDialog dialog;
    private WebView inAppWebView;
    private TextView pageTitle;
    private TextView urlLabel;
    public ImageButton back;
    public ImageButton forward;
    private CallbackContext callbackContext;
    private boolean showToolbar = true;
    private boolean showLocationBar = true;
    private boolean showZoomControls = true;
    private boolean openWindowHidden = false;
    private boolean clearAllCache= false;
    private boolean clearSessionCache=false;
    private boolean hadwareBackButton=true;
    public String leaveIabRegex = "";
    public String loadingCaption = "Laddar...";

    /**
     * Executes the request and returns PluginResult.
     *
     * @param action        The action to execute.
     * @param args          JSONArry of arguments for the plugin.
     * @param callbackId    The callback id used when calling back into JavaScript.
     * @return              A PluginResult object with a status and message.
     */
    public boolean execute(String action, CordovaArgs args, final CallbackContext callbackContext) throws JSONException {
        if (action.equals("open")) {
            this.callbackContext = callbackContext;
            final String url = args.getString(0);
            String t = args.optString(1);
            if (t == null || t.equals("") || t.equals(NULL)) {
                t = SELF;
            }
            final String target = t;
            final HashMap<String, Boolean> features = parseFeature(args.optString(2));
            
            // Get leave regex from options
            StringTokenizer featureStrs = new StringTokenizer(args.optString(2), ",");
            StringTokenizer option;
            while (featureStrs.hasMoreElements()) {
                option = new StringTokenizer(featureStrs.nextToken(), "=");
                if (option.hasMoreElements()) {
                    String key = option.nextToken();
                    if (key.equals(LEAVE_IAB_REGEX)) {
                        this.leaveIabRegex = option.nextToken();
                    }
                    else if (key.equals(LOADING_CAPTION)) {
                        this.loadingCaption = option.nextToken();
                    }
                }
            }

            Log.d(LOG_TAG, "leave regex = " + this.leaveIabRegex);
            Log.d(LOG_TAG, "target = " + target);
            Log.d(LOG_TAG, "url = " + url);

            final Pattern urlPattern     = Pattern.compile(this.leaveIabRegex);
            final Matcher urlMatcher     = urlPattern.matcher(url);
            final Boolean shouldLeaveIab = urlMatcher.find();

            Log.d(LOG_TAG, "leave iab = " + shouldLeaveIab);
            
            this.cordova.getActivity().runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    String result = "";
                    // SELF
                    if (SELF.equals(target)) {
                        Log.d(LOG_TAG, "in self");
                        /* This code exists for compatibility between 3.x and 4.x versions of Cordova.
                         * Previously the Config class had a static method, isUrlWhitelisted(). That
                         * responsibility has been moved to the plugins, with an aggregating method in
                         * PluginManager.
                         */
                        Boolean shouldAllowNavigation = null;
                        if (url.startsWith("javascript:")) {
                            shouldAllowNavigation = true;
                        }
                        if (shouldAllowNavigation == null) {
                            try {
                                Method iuw = Config.class.getMethod("isUrlWhiteListed", String.class);
                                shouldAllowNavigation = (Boolean)iuw.invoke(null, url);
                            } catch (NoSuchMethodException e) {
                            } catch (IllegalAccessException e) {
                            } catch (InvocationTargetException e) {
                            }
                        }
                        if (shouldAllowNavigation == null) {
                            try {
                                Method gpm = webView.getClass().getMethod("getPluginManager");
                                PluginManager pm = (PluginManager)gpm.invoke(webView);
                                Method san = pm.getClass().getMethod("shouldAllowNavigation", String.class);
                                shouldAllowNavigation = (Boolean)san.invoke(pm, url);
                            } catch (NoSuchMethodException e) {
                            } catch (IllegalAccessException e) {
                            } catch (InvocationTargetException e) {
                            }
                        }
                        // load in webview
                        if (Boolean.TRUE.equals(shouldAllowNavigation)) {
                            Log.d(LOG_TAG, "loading in webview");
                            webView.loadUrl(url);
                        }
                        //Load the dialer
                        else if (url.startsWith(WebView.SCHEME_TEL))
                        {
                            try {
                                Log.d(LOG_TAG, "loading in dialer");
                                Intent intent = new Intent(Intent.ACTION_DIAL);
                                intent.setData(Uri.parse(url));
                                cordova.getActivity().startActivity(intent);
                            } catch (android.content.ActivityNotFoundException e) {
                                LOG.e(LOG_TAG, "Error dialing " + url + ": " + e.toString());
                            }
                        }
                        // load in InAppBrowser
                        else {
                            Log.d(LOG_TAG, "loading in InAppBrowser");
                            result = showWebPage(url, features);
                        }
                    }
                    // SYSTEM
                    else if (SYSTEM.equals(target) || shouldLeaveIab) {
                        Log.d(LOG_TAG, "in system");
                        result = openExternal(url);
                    }
                    // BLANK - or anything else
                    else {
                        Log.d(LOG_TAG, "in blank");
                        result = showWebPage(url, features);
                    }
    
                    PluginResult pluginResult = new PluginResult(PluginResult.Status.OK, result);
                    pluginResult.setKeepCallback(true);
                    callbackContext.sendPluginResult(pluginResult);
                }
            });
        }
        else if (action.equals("close")) {
            closeDialog();
        }
        else if (action.equals("injectScriptCode")) {
            String jsWrapper = null;
            if (args.getBoolean(1)) {
                jsWrapper = String.format("prompt(JSON.stringify([eval(%%s)]), 'gap-iab://%s')", callbackContext.getCallbackId());
            }
            injectDeferredObject(args.getString(0), jsWrapper);
        }
        else if (action.equals("injectScriptFile")) {
            String jsWrapper;
            if (args.getBoolean(1)) {
                jsWrapper = String.format("(function(d) { var c = d.createElement('script'); c.src = %%s; c.onload = function() { prompt('', 'gap-iab://%s'); }; d.body.appendChild(c); })(document)", callbackContext.getCallbackId());
            } else {
                jsWrapper = "(function(d) { var c = d.createElement('script'); c.src = %s; d.body.appendChild(c); })(document)";
            }
            injectDeferredObject(args.getString(0), jsWrapper);
        }
        else if (action.equals("injectStyleCode")) {
            String jsWrapper;
            if (args.getBoolean(1)) {
                jsWrapper = String.format("(function(d) { var c = d.createElement('style'); c.innerHTML = %%s; d.body.appendChild(c); prompt('', 'gap-iab://%s');})(document)", callbackContext.getCallbackId());
            } else {
                jsWrapper = "(function(d) { var c = d.createElement('style'); c.innerHTML = %s; d.body.appendChild(c); })(document)";
            }
            injectDeferredObject(args.getString(0), jsWrapper);
        }
        else if (action.equals("injectStyleFile")) {
            String jsWrapper;
            if (args.getBoolean(1)) {
                jsWrapper = String.format("(function(d) { var c = d.createElement('link'); c.rel='stylesheet'; c.type='text/css'; c.href = %%s; d.head.appendChild(c); prompt('', 'gap-iab://%s');})(document)", callbackContext.getCallbackId());
            } else {
                jsWrapper = "(function(d) { var c = d.createElement('link'); c.rel='stylesheet'; c.type='text/css'; c.href = %s; d.head.appendChild(c); })(document)";
            }
            injectDeferredObject(args.getString(0), jsWrapper);
        }
        else if (action.equals("show")) {
            this.cordova.getActivity().runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    dialog.show();
                }
            });
            PluginResult pluginResult = new PluginResult(PluginResult.Status.OK);
            pluginResult.setKeepCallback(true);
            this.callbackContext.sendPluginResult(pluginResult);
        }
        else {
            return false;
        }
        return true;
    }

    /**
     * Called when the view navigates.
     */
    @Override
    public void onReset() {
        closeDialog();        
    }
    
    /**
     * Called by AccelBroker when listener is to be shut down.
     * Stop listener.
     */
    public void onDestroy() {
        closeDialog();
    }
    
    /**
     * Inject an object (script or style) into the InAppBrowser WebView.
     *
     * This is a helper method for the inject{Script|Style}{Code|File} API calls, which
     * provides a consistent method for injecting JavaScript code into the document.
     *
     * If a wrapper string is supplied, then the source string will be JSON-encoded (adding
     * quotes) and wrapped using string formatting. (The wrapper string should have a single
     * '%s' marker)
     *
     * @param source      The source object (filename or script/style text) to inject into
     *                    the document.
     * @param jsWrapper   A JavaScript string to wrap the source string in, so that the object
     *                    is properly injected, or null if the source string is JavaScript text
     *                    which should be executed directly.
     */
    private void injectDeferredObject(String source, String jsWrapper) {
        String scriptToInject;
        if (jsWrapper != null) {
            org.json.JSONArray jsonEsc = new org.json.JSONArray();
            jsonEsc.put(source);
            String jsonRepr = jsonEsc.toString();
            String jsonSourceString = jsonRepr.substring(1, jsonRepr.length()-1);
            scriptToInject = String.format(jsWrapper, jsonSourceString);
        } else {
            scriptToInject = source;
        }
        final String finalScriptToInject = scriptToInject;
        this.cordova.getActivity().runOnUiThread(new Runnable() {
            @SuppressLint("NewApi")
            @Override
            public void run() {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.KITKAT) {
                    // This action will have the side-effect of blurring the currently focused element
                    inAppWebView.loadUrl("javascript:" + finalScriptToInject);
                } else {
                    inAppWebView.evaluateJavascript(finalScriptToInject, null);
                }
            }
        });
    }

    /**
     * Put the list of features into a hash map
     * 
     * @param optString
     * @return
     */
    private HashMap<String, Boolean> parseFeature(String optString) {
        if (optString.equals(NULL)) {
            return null;
        } else {
            HashMap<String, Boolean> map = new HashMap<String, Boolean>();
            StringTokenizer features = new StringTokenizer(optString, ",");
            StringTokenizer option;
            while(features.hasMoreElements()) {
                option = new StringTokenizer(features.nextToken(), "=");
                if (option.hasMoreElements()) {
                    String key = option.nextToken();
                    Boolean value = option.nextToken().equals("no") ? Boolean.FALSE : Boolean.TRUE;
                    map.put(key, value);
                }
            }
            return map;
        }
    }

    /**
     * Display a new browser with the specified URL.
     *
     * @param url           The url to load.
     * @param usePhoneGap   Load url in PhoneGap webview
     * @return              "" if ok, or error message.
     */
    public String openExternal(String url) {
        try {
            Intent intent = null;
            intent = new Intent(Intent.ACTION_VIEW);
            // Omitting the MIME type for file: URLs causes "No Activity found to handle Intent".
            // Adding the MIME type to http: URLs causes them to not be handled by the downloader.
            Uri uri = Uri.parse(url);
            if ("file".equals(uri.getScheme())) {
                intent.setDataAndType(uri, webView.getResourceApi().getMimeType(uri));
            } else {
                intent.setData(uri);
            }
			intent.putExtra(Browser.EXTRA_APPLICATION_ID, cordova.getActivity().getPackageName());
            this.cordova.getActivity().startActivity(intent);
            return "";
        } catch (android.content.ActivityNotFoundException e) {
            Log.d(LOG_TAG, "InAppBrowser: Error loading url "+url+":"+ e.toString());
            return e.toString();
        }
    }

    /**
     * Closes the dialog
     */
    public void closeDialog() {
        final WebView childView = this.inAppWebView;
        // The JS protects against multiple calls, so this should happen only when
        // closeDialog() is called by other native code.
        if (childView == null) {
            return;
        }
        this.cordova.getActivity().runOnUiThread(new Runnable() {
            @Override
            public void run() {
                childView.setWebViewClient(new WebViewClient() {
                    // NB: wait for about:blank before dismissing
                    public void onPageFinished(WebView view, String url) {
                        if (dialog != null) {
                            dialog.dismiss();
                        }
                    }
                });
                // NB: From SDK 19: "If you call methods on WebView from any thread 
                // other than your app's UI thread, it can cause unexpected results."
                // http://developer.android.com/guide/webapps/migrating.html#Threads
                childView.loadUrl("about:blank");
            }
        });

        try {
            JSONObject obj = new JSONObject();
            obj.put("type", EXIT_EVENT);
            sendUpdate(obj, false);
        } catch (JSONException ex) {
            Log.d(LOG_TAG, "Should never happen");
        }
    }

    /**
     * Checks to see if it is possible to go back one page in history, then does so.
     */
    public void goBack() {
        if (this.inAppWebView.canGoBack()) {
            this.inAppWebView.goBack();
        }
    }

    /**
     * Can the web browser go back?
     * @return boolean
     */
    public boolean canGoBack() {
        return this.inAppWebView.canGoBack();
    }

    /**
     * Has the user set the hardware back button to go back
     * @return boolean
     */
    public boolean hardwareBack() {
        return hadwareBackButton;
    }

    /**
     * Checks to see if it is possible to go forward one page in history, then does so.
     */
    private void goForward() {
        if (this.inAppWebView.canGoForward()) {
            this.inAppWebView.goForward();
        }
    }

    /**
     * Can the web browser go forward?
     * @return boolean
     */
    public boolean canGoForward() {
        return this.inAppWebView.canGoForward();
    }

    /**
     * Navigate to the new page
     *
     * @param url to load
     */
    private void navigate(String url) {
        InputMethodManager imm = (InputMethodManager)this.cordova.getActivity().getSystemService(Context.INPUT_METHOD_SERVICE);
        imm.hideSoftInputFromWindow(urlLabel.getWindowToken(), 0);

        Log.d(LOG_TAG, "navigate = " + url);

        if (!url.startsWith("http") && !url.startsWith("file:")) {
            this.inAppWebView.loadUrl("http://" + url);
        } else {
            this.inAppWebView.loadUrl(url);
        }
        this.inAppWebView.requestFocus();
    }


    /**
     * Should we show the location bar?
     *
     * @return boolean
     */
    private boolean getShowLocationBar() {
        return this.showLocationBar;
    }

    /**
     * Should we show the toolbar?
     *
     * @return boolean
     */
    private boolean getShowToolbar() {
        return this.showToolbar;
    }

    /**
     * Should we show the zoom controls?
     *
     * @return boolean
     */
    private boolean getShowZoomControls() {
        return this.showZoomControls;
    }

    private InAppBrowser getInAppBrowser(){
        return this;
    }

    /**
     * Display a new browser with the specified URL.
     *
     * @param url           The url to load.
     * @param jsonObject
     */
    public String showWebPage(final String url, HashMap<String, Boolean> features) {
        // Determine if we should hide the location bar.
        showLocationBar = true;
        showToolbar = true;
        showZoomControls = true;
        openWindowHidden = false;
        if (features != null) {
            Boolean showLocationBarOpt = features.get(LOCATION);
            if (showLocationBarOpt != null) {
                showLocationBar = showLocationBarOpt.booleanValue();
            }
            Boolean showToolbarOpt = features.get(TOOLBAR);
            if (showToolbarOpt != null) {
                showToolbar = showToolbarOpt.booleanValue();
            }
            Boolean zoom = features.get(ZOOM);
            if (zoom != null) {
                showZoomControls = zoom.booleanValue();
            }            
            Boolean hidden = features.get(HIDDEN);
            if (hidden != null) {
                openWindowHidden = hidden.booleanValue();
            }
            Boolean hardwareBack = features.get(HARDWARE_BACK_BUTTON);
            if (hardwareBack != null) {
                hadwareBackButton = hardwareBack.booleanValue();
            }
            Boolean cache = features.get(CLEAR_ALL_CACHE);
            if (cache != null) {
                clearAllCache = cache.booleanValue();
            } else {
                cache = features.get(CLEAR_SESSION_CACHE);
                if (cache != null) {
                    clearSessionCache = cache.booleanValue();
                }
            }
        }
        

        final CordovaWebView thatWebView = this.webView;
        final InAppBrowser self = this;

        // Create dialog in new thread
        Runnable runnable = new Runnable() {
            /**
             * Convert our DIP units to Pixels
             *
             * @return int
             */
            private int dpToPixels(int dipValue) {
                int value = (int) TypedValue.applyDimension( TypedValue.COMPLEX_UNIT_DIP,
                                                            (float) dipValue,
                                                            cordova.getActivity().getResources().getDisplayMetrics()
                );

                return value;
            }

            @SuppressLint("NewApi")
            public void run() {
                // Let's create the main dialog
                dialog = new InAppBrowserDialog(cordova.getActivity(), android.R.style.Theme_NoTitleBar);
                dialog.getWindow().getAttributes().windowAnimations = android.R.style.Animation_Dialog;
                dialog.requestWindowFeature(Window.FEATURE_NO_TITLE);
                dialog.setCancelable(true);
                dialog.setInAppBroswer(getInAppBrowser());

                // Main container layout
                LinearLayout main = new LinearLayout(cordova.getActivity());
                main.setOrientation(LinearLayout.VERTICAL);

                // Toolbar layout
                LinearLayout toolbar = new LinearLayout(cordova.getActivity());
                toolbar.setOrientation(LinearLayout.HORIZONTAL);
                toolbar.setBackgroundColor(android.graphics.Color.argb(255, 232, 232, 232));
                toolbar.setLayoutParams(new RelativeLayout.LayoutParams(LayoutParams.MATCH_PARENT, this.dpToPixels(44)));
                toolbar.setPadding(0, 0, 0, 0);
                toolbar.setHorizontalGravity(Gravity.LEFT);
                toolbar.setVerticalGravity(Gravity.TOP);

                // Title and url container
                RelativeLayout pageInfoContainer = new RelativeLayout(cordova.getActivity());
                LinearLayout.LayoutParams pageInfoLayoutParams = new LinearLayout.LayoutParams(LayoutParams.FILL_PARENT, LayoutParams.WRAP_CONTENT, 1);
                // pageInfoLayoutParams.addRule(LinearLayout.ALIGN_PARENT_LEFT);
                pageInfoContainer.setLayoutParams(pageInfoLayoutParams);
                pageInfoContainer.setHorizontalGravity(Gravity.LEFT);
                pageInfoContainer.setVerticalGravity(Gravity.CENTER_VERTICAL);
                pageInfoContainer.setPadding(this.dpToPixels(2), this.dpToPixels(7), this.dpToPixels(2), this.dpToPixels(7));
                pageInfoContainer.setId(10);

                // Page title label
                pageTitle = new TextView(cordova.getActivity());
                RelativeLayout.LayoutParams pageTitleLayoutParams = new RelativeLayout.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT);
                pageTitle.setLayoutParams(pageTitleLayoutParams);
                pageTitle.setId(11);
                pageTitle.setSingleLine(true);
                pageTitle.setText(self.loadingCaption);
                pageTitle.setEllipsize(TextUtils.TruncateAt.END);
                pageTitle.setTextColor(android.graphics.Color.argb(255, 68, 68, 68));
                pageTitle.setTextSize(TypedValue.COMPLEX_UNIT_DIP, 13);
                pageTitle.setTypeface(android.graphics.Typeface.defaultFromStyle(android.graphics.Typeface.BOLD));
                pageTitle.setGravity(Gravity.LEFT | Gravity.TOP);

                // URL Label
                urlLabel = new TextView(cordova.getActivity());
                RelativeLayout.LayoutParams urlLayoutParams = new RelativeLayout.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT);
                urlLabel.setLayoutParams(urlLayoutParams);
                urlLabel.setId(4);
                urlLabel.setSingleLine(true);
                urlLabel.setText(url);
                urlLabel.setEllipsize(TextUtils.TruncateAt.END);
                urlLabel.setTextColor(android.graphics.Color.argb(255, 180, 180, 180));
                urlLabel.setTextSize(TypedValue.COMPLEX_UNIT_DIP, 10);
                urlLabel.setGravity(Gravity.LEFT | Gravity.BOTTOM);

                pageInfoContainer.addView(pageTitle);
                pageInfoContainer.addView(urlLabel);

                // Action Button Container layout
                LinearLayout actionButtonContainer = new LinearLayout(cordova.getActivity());
                LinearLayout.LayoutParams actionButtonLayoutParams = new LinearLayout.LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.FILL_PARENT, 0);
                // actionButtonLayoutParams.addRule(LinearLayout.LEFT_OF, 5);
                actionButtonContainer.setLayoutParams(actionButtonLayoutParams);
                actionButtonContainer.setHorizontalGravity(Gravity.LEFT);
                actionButtonContainer.setVerticalGravity(Gravity.CENTER_VERTICAL);
                actionButtonContainer.setPadding(0, 0, 0, 0);
                actionButtonContainer.setAlpha((float) 0.733); // #444
                actionButtonContainer.setId(1);

                Resources activityRes = cordova.getActivity().getResources();

                int buttonWidth  = this.dpToPixels(38);
                int buttonHeight = this.dpToPixels(44);

                // Back border
                View backBorder = new View(cordova.getActivity());
                RelativeLayout.LayoutParams backBorderLayoutParams = new RelativeLayout.LayoutParams(this.dpToPixels(1), LayoutParams.FILL_PARENT);
                backBorder.setLayoutParams(backBorderLayoutParams);
                backBorder.setBackgroundColor(android.graphics.Color.argb(255, 215, 215, 215));

                // Back button
                back = new ImageButton(cordova.getActivity());
                RelativeLayout.LayoutParams backLayoutParams = new RelativeLayout.LayoutParams(buttonWidth, buttonHeight);
                backLayoutParams.addRule(RelativeLayout.ALIGN_PARENT_LEFT);
                back.setLayoutParams(backLayoutParams);
                back.setPadding(this.dpToPixels(5), this.dpToPixels(12), this.dpToPixels(5), this.dpToPixels(12));
                back.setScaleType(ImageView.ScaleType.CENTER_INSIDE);
                // back.setBackgroundResource(0);
                back.setContentDescription("Back Button");
                back.setId(2);
                back.setImageResource(activityRes.getIdentifier("arrow_left", "drawable", cordova.getActivity().getPackageName()));
                back.setBackgroundResource(0);
                back.setAlpha((float) 0.25);

                back.setOnClickListener(new View.OnClickListener() {
                    public void onClick(View v) {
                        goBack();
                    }
                });

                // Forward border
                View forwardBorder = new View(cordova.getActivity());
                RelativeLayout.LayoutParams forwardBorderLayoutParams = new RelativeLayout.LayoutParams(this.dpToPixels(1), LayoutParams.FILL_PARENT);
                forwardBorder.setLayoutParams(forwardBorderLayoutParams);
                forwardBorder.setBackgroundColor(android.graphics.Color.argb(255, 215, 215, 215));

                // Forward button
                forward = new ImageButton(cordova.getActivity());
                RelativeLayout.LayoutParams forwardLayoutParams = new RelativeLayout.LayoutParams(buttonWidth, buttonHeight);
                // forwardLayoutParams.addRule(RelativeLayout.RIGHT_OF, 2);
                forward.setLayoutParams(forwardLayoutParams);
                forward.setPadding(this.dpToPixels(5), this.dpToPixels(12), this.dpToPixels(5), this.dpToPixels(12));
                forward.setScaleType(ImageView.ScaleType.CENTER_INSIDE);
                forward.setContentDescription("Forward Button");
                forward.setId(3);
                forward.setImageResource(activityRes.getIdentifier("arrow_right", "drawable", cordova.getActivity().getPackageName()));
                forward.setBackgroundResource(0);
                forward.setAlpha((float) 0.25);

                forward.setOnClickListener(new View.OnClickListener() {
                    public void onClick(View v) {
                        goForward();
                    }
                });

                // Close/Done button
                LinearLayout closeLayout = new LinearLayout(cordova.getActivity());
                LinearLayout.LayoutParams closeLayoutParams = new LinearLayout.LayoutParams(this.dpToPixels(45), this.dpToPixels(44), 0);
                closeLayout.setLayoutParams(closeLayoutParams);

                ImageButton close = new ImageButton(cordova.getActivity());
                RelativeLayout.LayoutParams closeLayoutBtnParams = new RelativeLayout.LayoutParams(this.dpToPixels(44), LayoutParams.FILL_PARENT);
                // closeLayoutBtnParams.addRule(RelativeLayout.ALIGN_PARENT_LEFT);
                close.setLayoutParams(closeLayoutBtnParams);
                close.setPadding(this.dpToPixels(12), this.dpToPixels(12), this.dpToPixels(12), this.dpToPixels(12));
                close.setScaleType(ImageView.ScaleType.CENTER_INSIDE);
                close.setContentDescription("Close Button");
                close.setId(5);
                close.setImageResource(activityRes.getIdentifier("close_2", "drawable", cordova.getActivity().getPackageName()));
                close.setBackgroundResource(0);

                close.setOnClickListener(new View.OnClickListener() {
                    public void onClick(View v) {
                        closeDialog();
                    }
                });

                View closeBorder = new View(cordova.getActivity());
                closeBorder.setBackgroundColor(android.graphics.Color.argb(255, 215, 215, 215));
                RelativeLayout.LayoutParams closeBorderLayoutParams = new RelativeLayout.LayoutParams(this.dpToPixels(1), LayoutParams.FILL_PARENT);
                closeBorderLayoutParams.addRule(RelativeLayout.ALIGN_PARENT_RIGHT);
                closeBorder.setLayoutParams(closeBorderLayoutParams);

                closeLayout.addView(close);
                // closeLayout.addView(closeBorder);

                // WebView
                inAppWebView = new WebView(cordova.getActivity());
                inAppWebView.setLayoutParams(new LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT));
                inAppWebView.setWebChromeClient(new InAppChromeClient(thatWebView));
                WebViewClient client = new InAppBrowserClient(self);
                inAppWebView.setWebViewClient(client);
                WebSettings settings = inAppWebView.getSettings();
                settings.setJavaScriptEnabled(true);
                settings.setJavaScriptCanOpenWindowsAutomatically(true);
                settings.setBuiltInZoomControls(getShowZoomControls());
                settings.setPluginState(android.webkit.WebSettings.PluginState.ON);

                //Toggle whether this is enabled or not!
                Bundle appSettings = cordova.getActivity().getIntent().getExtras();
                boolean enableDatabase = appSettings == null ? true : appSettings.getBoolean("InAppBrowserStorageEnabled", true);
                if (enableDatabase) {
                    String databasePath = cordova.getActivity().getApplicationContext().getDir("inAppBrowserDB", Context.MODE_PRIVATE).getPath();
                    settings.setDatabasePath(databasePath);
                    settings.setDatabaseEnabled(true);
                }
                settings.setDomStorageEnabled(true);

                if (clearAllCache) {
                    CookieManager.getInstance().removeAllCookie();
                } else if (clearSessionCache) {
                    CookieManager.getInstance().removeSessionCookie();
                }

                inAppWebView.loadUrl(url);
                inAppWebView.setId(6);
                inAppWebView.getSettings().setLoadWithOverviewMode(true);
                inAppWebView.getSettings().setUseWideViewPort(true);
                inAppWebView.requestFocus();
                inAppWebView.requestFocusFromTouch();

                // Add the back and forward buttons to our action button container layout
                // actionButtonContainer.addView(backBorder);
                actionButtonContainer.addView(back);
                // actionButtonContainer.addView(forwardBorder);
                actionButtonContainer.addView(forward);

                // Add the views to our toolbar
                toolbar.addView(closeLayout);
                toolbar.addView(pageInfoContainer);
                toolbar.addView(actionButtonContainer);

                // Don't add the toolbar if its been disabled
                if (getShowToolbar()) {
                    // Add our toolbar to our main view/layout
                    main.addView(toolbar);
                }

                // Add our webview to our main view/layout
                main.addView(inAppWebView);

                WindowManager.LayoutParams lp = new WindowManager.LayoutParams();
                lp.copyFrom(dialog.getWindow().getAttributes());
                lp.width = WindowManager.LayoutParams.MATCH_PARENT;
                lp.height = WindowManager.LayoutParams.MATCH_PARENT;

                dialog.setContentView(main);
                dialog.show();
                dialog.getWindow().setAttributes(lp);
                // the goal of openhidden is to load the url and not display it
                // Show() needs to be called to cause the URL to be loaded
                if(openWindowHidden) {
                    dialog.hide();
                }
            }
        };
        this.cordova.getActivity().runOnUiThread(runnable);
        return "";
    }

    /**
     * Create a new plugin success result and send it back to JavaScript
     *
     * @param obj a JSONObject contain event payload information
     */
    private void sendUpdate(JSONObject obj, boolean keepCallback) {
        sendUpdate(obj, keepCallback, PluginResult.Status.OK);
    }

    /**
     * Create a new plugin result and send it back to JavaScript
     *
     * @param obj a JSONObject contain event payload information
     * @param status the status code to return to the JavaScript environment
     */    
    private void sendUpdate(JSONObject obj, boolean keepCallback, PluginResult.Status status) {
        if (callbackContext != null) {
            PluginResult result = new PluginResult(status, obj);
            result.setKeepCallback(keepCallback);
            callbackContext.sendPluginResult(result);
            if (!keepCallback) {
                callbackContext = null;
            }
        }
    }
    
    /**
     * The webview client receives notifications about appView
     */
    public class InAppBrowserClient extends WebViewClient {
        InAppBrowser delegate;

        /**
         * Constructor.
         *
         * @param mContext
         * @param urlLabel
         */
        public InAppBrowserClient(InAppBrowser delegate) {
            this.delegate = delegate;
        }

        /**
         * Notify the host application that a page has started loading.
         *
         * @param view          The webview initiating the callback.
         * @param url           The url of the page.
         */
        @Override
        public void onPageStarted(WebView view, String url,  Bitmap favicon) {
            super.onPageStarted(view, url, favicon);
            String newloc = "";

            Pattern leaveRegexPattern = Pattern.compile(this.delegate.leaveIabRegex);
            Boolean shouldLeaveIab    = leaveRegexPattern.matcher(url).find();

            Log.d(LOG_TAG, "start loading url = " + url);
            Log.d(LOG_TAG, "compare against regex = " + this.delegate.leaveIabRegex);
            Log.d(LOG_TAG, "should leave iab = " + shouldLeaveIab);

            if (shouldLeaveIab) {
                Log.d(LOG_TAG, "leave and stop");
                view.stopLoading();
                this.delegate.openExternal(url);
                return;
            }
            else if (url.startsWith("http:") || url.startsWith("https:") || url.startsWith("file:")) {
                newloc = url;

                this.delegate.pageTitle.setText(this.delegate.loadingCaption);
                this.delegate.urlLabel.setText(url);
            } 
            // If dialing phone (tel:5551212)
            else if (url.startsWith(WebView.SCHEME_TEL)) {
                try {
                    Intent intent = new Intent(Intent.ACTION_DIAL);
                    intent.setData(Uri.parse(url));
                    cordova.getActivity().startActivity(intent);
                } catch (android.content.ActivityNotFoundException e) {
                    LOG.e(LOG_TAG, "Error dialing " + url + ": " + e.toString());
                }
            }

            else if (url.startsWith("geo:") || url.startsWith(WebView.SCHEME_MAILTO) || url.startsWith("market:")) {
                try {
                    Intent intent = new Intent(Intent.ACTION_VIEW);
                    intent.setData(Uri.parse(url));
                    cordova.getActivity().startActivity(intent);
                } catch (android.content.ActivityNotFoundException e) {
                    LOG.e(LOG_TAG, "Error with " + url + ": " + e.toString());
                }
            }
            // If sms:5551212?body=This is the message
            else if (url.startsWith("sms:")) {
                try {
                    Intent intent = new Intent(Intent.ACTION_VIEW);

                    // Get address
                    String address = null;
                    int parmIndex = url.indexOf('?');
                    if (parmIndex == -1) {
                        address = url.substring(4);
                    }
                    else {
                        address = url.substring(4, parmIndex);

                        // If body, then set sms body
                        Uri uri = Uri.parse(url);
                        String query = uri.getQuery();
                        if (query != null) {
                            if (query.startsWith("body=")) {
                                intent.putExtra("sms_body", query.substring(5));
                            }
                        }
                    }
                    intent.setData(Uri.parse("sms:" + address));
                    intent.putExtra("address", address);
                    intent.setType("vnd.android-dir/mms-sms");
                    cordova.getActivity().startActivity(intent);
                } catch (android.content.ActivityNotFoundException e) {
                    LOG.e(LOG_TAG, "Error sending sms " + url + ":" + e.toString());
                }
            }
            else {
                newloc = "http://" + url;
            }

            if (!newloc.equals(this.delegate.urlLabel.getText().toString())) {
                this.delegate.urlLabel.setText(newloc);
            }

            try {
                JSONObject obj = new JSONObject();
                obj.put("type", LOAD_START_EVENT);
                obj.put("url", newloc);
    
                sendUpdate(obj, true);
            } catch (JSONException ex) {
                Log.d(LOG_TAG, "Should never happen");
            }
        }
        
        public void onPageFinished(WebView view, String url) {
            super.onPageFinished(view, url);
            
            this.delegate.pageTitle.setText(view.getTitle());
            this.delegate.urlLabel.setText(url);

            this.delegate.back.setAlpha(   (float) (this.delegate.canGoBack()    ? 1.0 : 0.25));
            this.delegate.forward.setAlpha((float) (this.delegate.canGoForward() ? 1.0 : 0.25));

            try {
                JSONObject obj = new JSONObject();
                obj.put("type", LOAD_STOP_EVENT);
                obj.put("url", url);
    
                sendUpdate(obj, true);
            } catch (JSONException ex) {
                Log.d(LOG_TAG, "Should never happen");
            }
        }
        
        public void onReceivedError(WebView view, int errorCode, String description, String failingUrl) {
            super.onReceivedError(view, errorCode, description, failingUrl);
            
            try {
                JSONObject obj = new JSONObject();
                obj.put("type", LOAD_ERROR_EVENT);
                obj.put("url", failingUrl);
                obj.put("code", errorCode);
                obj.put("message", description);
    
                sendUpdate(obj, true, PluginResult.Status.ERROR);
            } catch (JSONException ex) {
                Log.d(LOG_TAG, "Should never happen");
            }
        }
    }
}
