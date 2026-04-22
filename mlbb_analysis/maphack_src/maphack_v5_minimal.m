/*
 * MLBB Map Hack v5 - Minimal Test
 * NO thread_attach - testing crash cause
 */

#import <Foundation/Foundation.h>
#include <pthread.h>

#define LOG(fmt, ...) NSLog(@"[MAPHACK_V5] " fmt, ##__VA_ARGS__)

static void* workerThread(void* arg) {
    LOG(@"Worker thread started");
    sleep(5);
    LOG(@"After 5s - dylib loaded OK!");
    
    while(1) {
        sleep(10);
        LOG(@"Still alive...");
    }
    return NULL;
}

__attribute__((constructor))
static void maphack_init(void) {
    LOG(@"Constructor called");
    pthread_t thread;
    pthread_create(&thread, NULL, workerThread, NULL);
    pthread_detach(thread);
    LOG(@"Constructor done");
}
