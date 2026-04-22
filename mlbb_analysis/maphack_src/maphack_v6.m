/*
 * MLBB Map Hack v6 - Wraith Constructor Pattern
 * 
 * STOLEN FROM WRAITH:
 * - Constructor только регистрирует NSURLProtocol, без UIKit
 * - pthread_create вместо dispatch_after
 * - @autoreleasepool вокруг NSLog
 * - Минимальная инициализация в constructor
 */

#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <string.h>
#include <mach/mach.h>
#include <pthread.h>

#define LOG(fmt, ...) do { \
    @autoreleasepool { \
        NSLog(@"[MAPHACK] " fmt, ##__VA_ARGS__); \
    } \
} while(0)

static BOOL safeWrite(void* addr, uint8_t val) {
    if (!addr || (uintptr_t)addr < 0x10000) {
        return NO;
    }
    
    vm_address_t newAddr = 0;
    vm_prot_t curProt, maxProt;
    kern_return_t kr = vm_remap(mach_task_self(), &newAddr, 1, 0, VM_FLAGS_ANYWHERE,
                                mach_task_self(), (vm_address_t)addr,
                                FALSE, &curProt, &maxProt, VM_INHERIT_SHARE);
    if (kr == KERN_SUCCESS) {
        *(uint8_t*)newAddr = val;
        vm_deallocate(mach_task_self(), newAddr, 1);
        return YES;
    }
    
    *(uint8_t*)addr = val;
    return YES;
}

typedef void* Il2CppDomain;
typedef void* Il2CppAssembly;
typedef void* Il2CppImage;
typedef void* Il2CppClass;
typedef void* FieldInfo;
typedef void* Il2CppThread;

typedef Il2CppDomain*    (*fn_domain_get_t)(void);
typedef Il2CppAssembly** (*fn_domain_get_assemblies_t)(Il2CppDomain* domain, size_t* size);
typedef Il2CppImage*     (*fn_assembly_get_image_t)(Il2CppAssembly* assembly);
typedef const char*      (*fn_image_get_name_t)(Il2CppImage* image);
typedef Il2CppClass*     (*fn_class_from_name_t)(Il2CppImage* image, const char* ns, const char* name);
typedef FieldInfo*       (*fn_class_get_field_t)(Il2CppClass* klass, const char* name);
typedef size_t           (*fn_field_get_offset_t)(FieldInfo* field);
typedef void*            (*fn_class_get_static_data_t)(Il2CppClass* klass);
typedef void             (*fn_class_init_t)(Il2CppClass* klass);
typedef Il2CppThread*    (*fn_thread_attach_t)(Il2CppDomain* domain);

static fn_domain_get_t            g_domain_get;
static fn_domain_get_assemblies_t g_domain_get_assemblies;
static fn_assembly_get_image_t    g_assembly_get_image;
static fn_image_get_name_t        g_image_get_name;
static fn_class_from_name_t       g_class_from_name;
static fn_class_get_field_t       g_class_get_field;
static fn_field_get_offset_t      g_field_get_offset;
static fn_class_get_static_data_t g_class_get_static_data;
static fn_class_init_t            g_class_init;
static fn_thread_attach_t         g_thread_attach;

static size_t off_m_ShowPlayers     = 0;
static size_t off_ShowEntity        = 0;
static size_t off_m_LocalPlayerShow = 0;
static void*  bm_static_data        = NULL;
static pthread_t g_thread;
static volatile int g_running = 1;

static BOOL loadIl2Cpp(void) {
    const char* uf_path = NULL;
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char* name = _dyld_get_image_name(i);
        if (name && strstr(name, "UnityFramework")) {
            uf_path = name;
            break;
        }
    }
    
    if (!uf_path) {
        LOG(@"UnityFramework not found");
        return NO;
    }
    
    void* h = dlopen(uf_path, RTLD_LAZY | RTLD_NOLOAD);
    if (!h) {
        LOG(@"dlopen failed: %s", dlerror());
        return NO;
    }
    
    g_domain_get            = (fn_domain_get_t)dlsym(h, "il2cpp_domain_get");
    g_domain_get_assemblies = (fn_domain_get_assemblies_t)dlsym(h, "il2cpp_domain_get_assemblies");
    g_assembly_get_image    = (fn_assembly_get_image_t)dlsym(h, "il2cpp_assembly_get_image");
    g_image_get_name        = (fn_image_get_name_t)dlsym(h, "il2cpp_image_get_name");
    g_class_from_name       = (fn_class_from_name_t)dlsym(h, "il2cpp_class_from_name");
    g_class_get_field       = (fn_class_get_field_t)dlsym(h, "il2cpp_class_get_field_from_name");
    g_field_get_offset      = (fn_field_get_offset_t)dlsym(h, "il2cpp_field_get_offset");
    g_class_get_static_data = (fn_class_get_static_data_t)dlsym(h, "il2cpp_class_get_static_field_data");
    g_class_init            = (fn_class_init_t)dlsym(h, "il2cpp_class_init");
    g_thread_attach         = (fn_thread_attach_t)dlsym(h, "il2cpp_thread_attach");
    
    if (!g_domain_get || !g_class_from_name || !g_thread_attach) {
        LOG(@"il2cpp functions not found");
        return NO;
    }
    
    LOG(@"il2cpp loaded");
    return YES;
}

static void findOffsets(void) {
    if (!g_domain_get) return;
    
    Il2CppDomain* domain = g_domain_get();
    if (!domain) {
        LOG(@"domain NULL");
        return;
    }
    
    // CRITICAL: attach thread to il2cpp domain
    if (g_thread_attach) {
        Il2CppThread* thread = g_thread_attach(domain);
        if (!thread) {
            LOG(@"thread_attach failed");
            return;
        }
        LOG(@"thread attached");
    }
    
    size_t count = 0;
    Il2CppAssembly** assemblies = g_domain_get_assemblies(domain, &count);
    if (!assemblies) {
        LOG(@"assemblies NULL");
        return;
    }
    
    Il2CppImage* img = NULL;
    for (size_t i = 0; i < count; i++) {
        Il2CppImage* im = g_assembly_get_image(assemblies[i]);
        if (!im) continue;
        const char* n = g_image_get_name(im);
        if (n && strcmp(n, "Assembly-CSharp.dll") == 0) {
            img = im;
            break;
        }
    }
    
    if (!img) {
        LOG(@"Assembly-CSharp.dll not found");
        return;
    }
    
    Il2CppClass* bm = g_class_from_name(img, "", "BattleManager");
    if (!bm) {
        LOG(@"BattleManager not found");
        return;
    }
    
    if (g_class_init) {
        g_class_init(bm);
    }
    
    if (g_class_get_static_data) {
        bm_static_data = g_class_get_static_data(bm);
    }
    
    FieldInfo* f;
    if ((f = g_class_get_field(bm, "m_ShowPlayers"))) {
        off_m_ShowPlayers = g_field_get_offset(f);
        LOG(@"m_ShowPlayers = 0x%zx", off_m_ShowPlayers);
    }
    
    if ((f = g_class_get_field(bm, "ShowEntity"))) {
        off_ShowEntity = g_field_get_offset(f);
        LOG(@"ShowEntity = 0x%zx", off_ShowEntity);
    }
    
    if ((f = g_class_get_field(bm, "m_LocalPlayerShow"))) {
        off_m_LocalPlayerShow = g_field_get_offset(f);
        LOG(@"m_LocalPlayerShow = 0x%zx", off_m_LocalPlayerShow);
    }
}

static void* workerThread(void* arg) {
    LOG(@"worker started, waiting 15s...");
    sleep(15);
    
    if (!loadIl2Cpp()) {
        LOG(@"loadIl2Cpp failed");
        return NULL;
    }
    
    for (int attempt = 0; attempt < 10 && g_running; attempt++) {
        LOG(@"attempt %d/10", attempt + 1);
        findOffsets();
        
        if (bm_static_data && off_m_ShowPlayers > 0) {
            LOG(@"offsets found!");
            break;
        }
        
        sleep(5);
    }
    
    if (!bm_static_data || off_m_ShowPlayers == 0) {
        LOG(@"offsets not found after 10 attempts");
        return NULL;
    }
    
    LOG(@"starting main loop");
    int tick = 0;
    while (g_running) {
        if (bm_static_data && off_m_ShowPlayers > 0) {
            void* bm = *(void* volatile*)bm_static_data;
            
            if (bm && (uintptr_t)bm > 0x10000) {
                if (tick % 10 == 0) {
                    LOG(@"BM=%p, writing...", bm);
                }
                
                safeWrite((uint8_t*)bm + off_m_ShowPlayers, 1);
                if (off_ShowEntity > 0)        safeWrite((uint8_t*)bm + off_ShowEntity, 1);
                if (off_m_LocalPlayerShow > 0) safeWrite((uint8_t*)bm + off_m_LocalPlayerShow, 1);
                
                tick++;
            }
        }
        
        usleep(500000); // 500ms
    }
    
    LOG(@"worker exit");
    return NULL;
}

// WRAITH PATTERN: constructor только создаёт pthread, без UIKit/NSLog
__attribute__((constructor))
static void maphack_init(void) {
    pthread_create(&g_thread, NULL, workerThread, NULL);
    pthread_detach(g_thread);
}
