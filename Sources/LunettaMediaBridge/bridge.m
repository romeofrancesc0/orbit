// Ponte verso Now Playing.
//
// Da macOS 15.4 MediaRemote risponde con dati vuoti ai processi qualunque e solo
// ad alcuni binari di sistema dà le informazioni vere. Questa libreria viene quindi
// caricata da /usr/bin/perl (vedi MediaBridgeProcess.swift) e scrive su stdout una
// riga JSON a ogni cambiamento. I comandi (play, avanti, scrub…) non hanno questo
// limite e l'app li invia direttamente da sé.

#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <stdio.h>
#include <unistd.h>

typedef void (*MRGetInfoFn)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef void (*MRGetPlayingFn)(dispatch_queue_t, void (^)(Boolean));
typedef void (*MRGetClientFn)(dispatch_queue_t, void (^)(id));
typedef void (*MRRegisterFn)(dispatch_queue_t);

static MRGetInfoFn getInfo;
static MRGetPlayingFn getPlaying;
static MRGetClientFn getClient;

static NSDictionary *lastState;
static NSData *lastArtwork;
static BOOL refreshPending;

static NSString *InfoKey(NSString *suffix) {
    return [@"kMRMediaRemoteNowPlayingInfo" stringByAppendingString:suffix];
}

static void CopyString(NSMutableDictionary *state, NSString *key, id value) {
    if ([value isKindOfClass:NSString.class] && [value length] > 0) state[key] = value;
}

static void CopyNumber(NSMutableDictionary *state, NSString *key, id value) {
    if ([value isKindOfClass:NSNumber.class]) state[key] = value;
}

static NSString *ClientString(id client, SEL selector) {
    if (!client || ![client respondsToSelector:selector]) return nil;
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    id value = [client performSelector:selector];
    #pragma clang diagnostic pop
    return [value isKindOfClass:NSString.class] ? value : nil;
}

static void WriteLine(NSDictionary *payload) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (!json) return;
    fwrite(json.bytes, 1, json.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

static void Emit(NSDictionary *info, BOOL playing, id client) {
    NSMutableDictionary *state = [NSMutableDictionary dictionary];
    state[@"playing"] = @(playing);

    CopyString(state, @"title", info[InfoKey(@"Title")]);
    CopyString(state, @"artist", info[InfoKey(@"Artist")]);
    CopyString(state, @"album", info[InfoKey(@"Album")]);
    CopyNumber(state, @"duration", info[InfoKey(@"Duration")]);
    CopyNumber(state, @"elapsed", info[InfoKey(@"ElapsedTime")]);
    CopyNumber(state, @"rate", info[InfoKey(@"PlaybackRate")]);
    CopyNumber(state, @"shuffle", info[InfoKey(@"ShuffleMode")]);
    CopyNumber(state, @"repeat", info[InfoKey(@"RepeatMode")]);

    id artworkID = info[InfoKey(@"ArtworkIdentifier")];
    CopyString(state, @"artworkID", artworkID);

    id timestamp = info[InfoKey(@"Timestamp")];
    if ([timestamp isKindOfClass:NSDate.class]) state[@"timestamp"] = @([timestamp timeIntervalSince1970]);

    CopyString(state, @"bundle", ClientString(client, NSSelectorFromString(@"bundleIdentifier")));
    CopyString(state, @"parent", ClientString(client, NSSelectorFromString(@"parentApplicationBundleIdentifier")));
    CopyString(state, @"name", ClientString(client, NSSelectorFromString(@"displayName")));

    // La copertina arriva spesso in un secondo momento: si invia solo quando cambia.
    id artwork = info[InfoKey(@"ArtworkData")];
    BOOL newArtwork = [artwork isKindOfClass:NSData.class] && ![artwork isEqual:lastArtwork];
    if (!newArtwork && [state isEqual:lastState]) return;

    lastState = [state copy];
    if (newArtwork) {
        lastArtwork = artwork;
        NSMutableDictionary *payload = [state mutableCopy];
        payload[@"artwork"] = [artwork base64EncodedStringWithOptions:0];
        WriteLine(payload);
    } else {
        WriteLine(state);
    }
}

static void Refresh(void) {
    dispatch_queue_t queue = dispatch_get_main_queue();
    getInfo(queue, ^(CFDictionaryRef raw) {
        NSDictionary *info = (__bridge NSDictionary *)raw ?: @{};
        getPlaying(queue, ^(Boolean playing) {
            getClient(queue, ^(id client) {
                Emit(info, playing, client);
            });
        });
    });
}

// I cambiamenti arrivano a raffica: se ne fa una lettura sola.
static void ScheduleRefresh(void) {
    if (refreshPending) return;
    refreshPending = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 80 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        refreshPending = NO;
        Refresh();
    });
}

// Installata da perl come una sub: gli argomenti che riceve non servono e non ritorna mai.
__attribute__((visibility("default")))
void lunetta_media_stream(void) {
    void *framework = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    if (!framework) {
        fprintf(stderr, "MediaRemote non disponibile\n");
        exit(2);
    }

    getInfo = (MRGetInfoFn)dlsym(framework, "MRMediaRemoteGetNowPlayingInfo");
    getPlaying = (MRGetPlayingFn)dlsym(framework, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    getClient = (MRGetClientFn)dlsym(framework, "MRMediaRemoteGetNowPlayingClient");
    MRRegisterFn registerFn = (MRRegisterFn)dlsym(framework, "MRMediaRemoteRegisterForNowPlayingNotifications");
    if (!getInfo || !getPlaying || !getClient || !registerFn) {
        fprintf(stderr, "Simboli di MediaRemote mancanti\n");
        exit(3);
    }

    dispatch_queue_t queue = dispatch_get_main_queue();
    registerFn(queue);

    NSArray *names = @[
        @"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
        @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
        @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
        @"kMRMediaRemoteNowPlayingApplicationClientStateDidChange"
    ];
    for (NSString *name in names) {
        [[NSNotificationCenter defaultCenter] addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
            ScheduleRefresh();
        }];
    }

    // Se l'app si chiude o va in crash, il ponte non deve restarle in giro.
    dispatch_source_t parent = dispatch_source_create(DISPATCH_SOURCE_TYPE_PROC, (uintptr_t)getppid(), DISPATCH_PROC_EXIT, queue);
    dispatch_source_set_event_handler(parent, ^{ exit(0); });
    dispatch_resume(parent);

    Refresh();
    CFRunLoopRun();
    (void)parent;
}
