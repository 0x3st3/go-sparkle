#define BUILDING_SPARKLE_SOURCES_EXTERNALLY

#import <Foundation/Foundation.h>
#import <Headers/SUUpdater.h>
#import <objc/runtime.h> // Required for class_addMethod()

static SUUpdater *updater = nil;

// -[SUUpdater setFeedURL:] persists the URL in the host bundle's user defaults,
// which is unsafe for feed URLs carrying a short-lived credential. The delegate
// is asked for the URL on every check and stores nothing.
static NSString *dynamicFeedURL = nil;

@interface GoSparkleUpdaterDelegate : NSObject <SUUpdaterDelegate>
@end

@implementation GoSparkleUpdaterDelegate
- (NSString *)feedURLStringForUpdater:(SUUpdater *)theUpdater {
  (void)theUpdater;
  return dynamicFeedURL;
}
@end

static GoSparkleUpdaterDelegate *updaterDelegate = nil;

void sparkle_initialize() {
  if (!updater) {
    updater = [[SUUpdater sharedUpdater] retain];
    updaterDelegate = [[GoSparkleUpdaterDelegate alloc] init];
    [updater setDelegate:updaterDelegate];
  }
}

void sparkle_setDynamicFeedURL(const char *feedURL) {
  NSString *next = feedURL ? [@(feedURL) copy] : nil;
  [dynamicFeedURL release];
  dynamicFeedURL = next;
}

void sparkle_checkForUpdates() { [updater checkForUpdates:updater]; }

void sparkle_checkForUpdatesInBackground() {
  [updater checkForUpdatesInBackground];
}

void sparkle_setAutomaticallyChecksForUpdates(int check) {
  [updater setAutomaticallyChecksForUpdates:check];
}

int sparkle_automaticallyChecksForUpdates() {
  return [updater automaticallyChecksForUpdates];
}

void sparkle_setAutomaticallyDownloadsUpdates(int check) {
  [updater setAutomaticallyDownloadsUpdates:check];
}

int sparkle_automaticallyDownloadsUpdates() {
  return [updater automaticallyDownloadsUpdates];
}

void sparkle_setUpdateCheckInterval(int interval) {
  [updater setUpdateCheckInterval:interval];
}

int sparkle_updateCheckInterval() { return [updater updateCheckInterval]; }

void sparkle_checkForUpdateInformation() {
  [updater checkForUpdateInformation];
}

void sparkle_setFeedURL(const char *feedURL) {
  [updater setFeedURL:[NSURL URLWithString:@(feedURL)]];
}

const char *sparkle_feedURL() {
  return [[[updater feedURL] absoluteString] UTF8String];
}

void sparkle_setUserAgentString(const char *ua) {
  [updater setUserAgentString:@(ua)];
}

const char *sparkle_userAgentString() {
  return [[updater userAgentString] UTF8String];
}

void sparkle_setSendsSystemProfile(int check) {
  [updater setSendsSystemProfile:check];
}

int sparkle_sendsSystemProfile() { return [updater sendsSystemProfile]; }

void sparkle_setDecryptionPassword(const char *pw) {
  [updater setDecryptionPassword:@(pw)];
}

const char *sparkle_decryptionPassword() {
  return [[updater decryptionPassword] UTF8String];
}

double sparkle_lastUpdateCheckDate() {
  return [[updater lastUpdateCheckDate] timeIntervalSince1970];
}

void sparkle_resetUpdateCycle() { [updater resetUpdateCycle]; }

int sparkle_updateInProgress() { return [updater updateInProgress]; }
