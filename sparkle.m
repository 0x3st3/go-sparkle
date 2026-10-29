#define BUILDING_SPARKLE_SOURCES_EXTERNALLY

#import <Foundation/Foundation.h>
#import <Headers/SPUUpdater.h>
#import <Headers/SPUUpdaterDelegate.h>
#import <Headers/SPUUserDriver.h>
#import <Headers/SUAppcastItem.h>
#import <Headers/SUUpdatePermissionResponse.h>
#import <Headers/SUUpdater.h>
#import <objc/runtime.h> // Required for class_addMethod()

// -[SUUpdater setFeedURL:] persists the URL in the host bundle's user defaults,
// which is unsafe for feed URLs carrying a short-lived credential. The delegates
// are asked for the URL on every check and store nothing.
static NSString *dynamicFeedURL = nil;

@interface GoSparkleUpdaterDelegate : NSObject <SUUpdaterDelegate>
@end

@implementation GoSparkleUpdaterDelegate
- (NSString *)feedURLStringForUpdater:(SUUpdater *)theUpdater {
  (void)theUpdater;
  return dynamicFeedURL;
}
@end

static SUUpdater *updater = nil;
static GoSparkleUpdaterDelegate *updaterDelegate = nil;

// Created on first use so an app that only installs silently never runs a
// second update cycle for its bundle.
static SUUpdater *legacyUpdater() {
  void (^create)(void) = ^{
    if (!updater) {
      updater = [[SUUpdater sharedUpdater] retain];
      updaterDelegate = [[GoSparkleUpdaterDelegate alloc] init];
      [updater setDelegate:updaterDelegate];
    }
  };
  if ([NSThread isMainThread]) {
    create();
  } else {
    dispatch_sync(dispatch_get_main_queue(), create);
  }
  return updater;
}

extern void goSparkleInstallDownloading(unsigned long long downloaded, unsigned long long total);
extern void goSparkleInstallExtracting(void);
extern void goSparkleInstallInstalling(void);
extern void goSparkleInstallFailed(char *reason);

// Set while a check started by InstallSilently has not yet failed or reached the installer.
static BOOL silentInstall = NO;
static uint64_t downloadedLength = 0;
static uint64_t expectedLength = 0;

static void failSilentInstall(NSString *reason) {
  if (!silentInstall) {
    return;
  }
  silentInstall = NO;
  goSparkleInstallFailed((char *)[reason UTF8String]);
}

@interface GoSparkleInstallDelegate : NSObject <SPUUpdaterDelegate>
@end

@implementation GoSparkleInstallDelegate
- (NSString *)feedURLStringForUpdater:(SPUUpdater *)theUpdater {
  (void)theUpdater;
  return dynamicFeedURL;
}
@end

// Answers every prompt with install and reports progress instead of showing a window.
@interface GoSparkleSilentUserDriver : NSObject <SPUUserDriver>
@end

@implementation GoSparkleSilentUserDriver
- (void)showUpdatePermissionRequest:(SPUUpdatePermissionRequest *)request
                              reply:(void (^)(SUUpdatePermissionResponse *))reply {
  (void)request;
  reply([[[SUUpdatePermissionResponse alloc] initWithAutomaticUpdateChecks:NO
                                                         sendSystemProfile:NO] autorelease]);
}

- (void)showUserInitiatedUpdateCheckWithCancellation:(void (^)(void))cancellation {
  (void)cancellation;
}

- (void)showUpdateFoundWithAppcastItem:(SUAppcastItem *)appcastItem
                                 state:(SPUUserUpdateState *)state
                                 reply:(void (^)(SPUUserUpdateChoice))reply {
  (void)state;
  if (appcastItem.informationOnlyUpdate) {
    failSilentInstall(@"The update has no download for this app");
    reply(SPUUserUpdateChoiceDismiss);
    return;
  }
  reply(SPUUserUpdateChoiceInstall);
}

- (void)showUpdateReleaseNotesWithDownloadData:(SPUDownloadData *)downloadData {
  (void)downloadData;
}

- (void)showUpdateReleaseNotesFailedToDownloadWithError:(NSError *)error {
  (void)error;
}

- (void)showUpdateNotFoundWithError:(NSError *)error acknowledgement:(void (^)(void))acknowledgement {
  failSilentInstall([error localizedDescription]);
  acknowledgement();
}

- (void)showUpdaterError:(NSError *)error acknowledgement:(void (^)(void))acknowledgement {
  failSilentInstall([error localizedDescription]);
  acknowledgement();
}

- (void)showDownloadInitiatedWithCancellation:(void (^)(void))cancellation {
  (void)cancellation;
  downloadedLength = 0;
  expectedLength = 0;
  goSparkleInstallDownloading(downloadedLength, expectedLength);
}

- (void)showDownloadDidReceiveExpectedContentLength:(uint64_t)expectedContentLength {
  expectedLength = expectedContentLength;
  goSparkleInstallDownloading(downloadedLength, expectedLength);
}

- (void)showDownloadDidReceiveDataOfLength:(uint64_t)length {
  downloadedLength += length;
  goSparkleInstallDownloading(downloadedLength, expectedLength);
}

- (void)showDownloadDidStartExtractingUpdate {
  goSparkleInstallExtracting();
}

- (void)showExtractionReceivedProgress:(double)progress {
  (void)progress;
}

- (void)showReadyToInstallAndRelaunch:(void (^)(SPUUserUpdateChoice))reply {
  reply(SPUUserUpdateChoiceInstall);
}

- (void)showInstallingUpdateWithApplicationTerminated:(BOOL)applicationTerminated
                          retryTerminatingApplication:(void (^)(void))retryTerminatingApplication {
  (void)applicationTerminated;
  (void)retryTerminatingApplication;
  if (silentInstall) {
    silentInstall = NO;
    goSparkleInstallInstalling();
  }
}

- (void)showUpdateInstalledAndRelaunched:(BOOL)relaunched acknowledgement:(void (^)(void))acknowledgement {
  (void)relaunched;
  acknowledgement();
}

- (void)dismissUpdateInstallation {
  failSilentInstall(@"The update ended before it was installed");
}
@end

static SPUUpdater *silentUpdater = nil;
static GoSparkleSilentUserDriver *silentUserDriver = nil;
static GoSparkleInstallDelegate *silentDelegate = nil;

// Swapped on the main thread, where Sparkle reads it, so a check never sees a released URL.
void sparkle_setDynamicFeedURL(const char *feedURL) {
  NSString *next = feedURL ? [@(feedURL) copy] : nil;
  dispatch_async(dispatch_get_main_queue(), ^{
    [dynamicFeedURL release];
    dynamicFeedURL = next;
  });
}

void sparkle_checkForUpdates() { [legacyUpdater() checkForUpdates:legacyUpdater()]; }

void sparkle_installSilently() {
  dispatch_async(dispatch_get_main_queue(), ^{
    silentInstall = YES;
    if (!silentUpdater) {
      if (!silentUserDriver) {
        silentUserDriver = [[GoSparkleSilentUserDriver alloc] init];
        silentDelegate = [[GoSparkleInstallDelegate alloc] init];
      }
      NSBundle *bundle = [NSBundle mainBundle];
      SPUUpdater *next = [[SPUUpdater alloc] initWithHostBundle:bundle
                                              applicationBundle:bundle
                                                     userDriver:silentUserDriver
                                                       delegate:silentDelegate];
      NSError *error = nil;
      if (![next startUpdater:&error]) {
        [next release];
        failSilentInstall([error localizedDescription]);
        return;
      }
      silentUpdater = next;
    }
    if ([silentUpdater sessionInProgress]) {
      failSilentInstall(@"An update is already in progress");
      return;
    }
    [silentUpdater checkForUpdates];
  });
}

void sparkle_checkForUpdatesInBackground() {
  [legacyUpdater() checkForUpdatesInBackground];
}

void sparkle_setAutomaticallyChecksForUpdates(int check) {
  [legacyUpdater() setAutomaticallyChecksForUpdates:check];
}

int sparkle_automaticallyChecksForUpdates() {
  return [legacyUpdater() automaticallyChecksForUpdates];
}

void sparkle_setAutomaticallyDownloadsUpdates(int check) {
  [legacyUpdater() setAutomaticallyDownloadsUpdates:check];
}

int sparkle_automaticallyDownloadsUpdates() {
  return [legacyUpdater() automaticallyDownloadsUpdates];
}

void sparkle_setUpdateCheckInterval(int interval) {
  [legacyUpdater() setUpdateCheckInterval:interval];
}

int sparkle_updateCheckInterval() { return [legacyUpdater() updateCheckInterval]; }

void sparkle_checkForUpdateInformation() {
  [legacyUpdater() checkForUpdateInformation];
}

void sparkle_setFeedURL(const char *feedURL) {
  [legacyUpdater() setFeedURL:[NSURL URLWithString:@(feedURL)]];
}

const char *sparkle_feedURL() {
  return [[[legacyUpdater() feedURL] absoluteString] UTF8String];
}

void sparkle_setUserAgentString(const char *ua) {
  [legacyUpdater() setUserAgentString:@(ua)];
}

const char *sparkle_userAgentString() {
  return [[legacyUpdater() userAgentString] UTF8String];
}

void sparkle_setSendsSystemProfile(int check) {
  [legacyUpdater() setSendsSystemProfile:check];
}

int sparkle_sendsSystemProfile() { return [legacyUpdater() sendsSystemProfile]; }

void sparkle_setDecryptionPassword(const char *pw) {
  [legacyUpdater() setDecryptionPassword:@(pw)];
}

const char *sparkle_decryptionPassword() {
  return [[legacyUpdater() decryptionPassword] UTF8String];
}

double sparkle_lastUpdateCheckDate() {
  return [[legacyUpdater() lastUpdateCheckDate] timeIntervalSince1970];
}

void sparkle_resetUpdateCycle() { [legacyUpdater() resetUpdateCycle]; }

int sparkle_updateInProgress() { return [legacyUpdater() updateInProgress]; }
