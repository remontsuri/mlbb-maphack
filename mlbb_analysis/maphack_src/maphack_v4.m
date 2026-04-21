/*
 * MLBB Map Hack v4 - Deep Analysis Version
 * - Added il2cpp_thread_attach
 * - Added extensive logging
 * - Better error handling
 * - Checks for NULL pointers
 */

#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <string.h>
#include <mach/mach.h>
#include <pthread.h>
#include <os/log.h>

#define LOG(fmt, ...) NSLog(@"[MAPHACK] " fmt, ##__VA_ARGS__)

static BOOL safeWrite(void* addr, uint8_t val) {
    if (!addr || (uintptr_t)addr < 0x10000) {
        LOG(@"safeWrite: invalid addr %p", addr);
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
        LOG(@"safeWrite: vm_remap success at %p -> %p", addr, (void*)newAddr);
        return YES;
    }
    
    LOG(@"safeWrite: vm_remap failed (kr=%d), trying direct write", kr);
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
    LOG(@"loadIl2Cpp: searching for UnityFramework...");
    
    const char* uf_path = NULL;
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char* name = _dyld_get_image_name(i);
        if (name && strstr(name, "UnityFramework")) {
            uf_path = name;
            LOG(@"loadIl2Cpp: found UnityFramework at %s", name);
            break;
        }
    }
    
    if (!uf_path) {
        LOG(@"loadIl2Cpp: UnityFramework not found!");
        return NO;
    }
    
    void* h = dlopen(uf_path, RTLD_LAZY | RTLD_NOLOAD);
    if (!h) {
        LOG(@"loadIl2Cpp: dlopen failed: %s", dlerror());
        return NO;
    }
    
    LOG(@"loadIl2Cpp: loading il2cpp functions...");
    
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
    
    if (!g_domain_get) {
        LOG(@"loadIl2Cpp: il2cpp_domain_get not found!");
        return NO;
    }
    if (!g_class_from_name) {
        LOG(@"loadIl2Cpp: il2cpp_class_from_name not found!");
        return NO;
    }
    if (!g_thread_attach) {
        LOG(@"loadIl2Cpp: il2cpp_thread_attach not found!");
        return NO;
    }
    
    LOG(@"loadIl2Cpp: all functions loaded successfully");
    return YES;
}

static void findOffsets(void) {
    LOG(@"findOffsets: starting...");
    
    if (!g_domain_get) {
        LOG(@"findOffsets: g_domain_get is NULL!");
        return;
    }
    
    Il2CppDomain* domain = g_domain_get();
    if (!domain) {
        LOG(@"findOffsets: il2cpp_domain_get() returned NULL!");
        return;
    }
    LOG(@"findOffsets: domain = %p", domain);
    
    // Attach thread to il2cpp domain
    if (g_thread_attach) {
        Il2CppThread* thread = g_thread_attach(domain);
        LOG(@"findOffsets: il2cpp_thread_attach() returned %p", thread);
    }
    
    size_t count = 0;
    Il2CppAssembly** assemblies = g_domain_get_assemblies(domain, &count);
    if (!assemblies) {
        LOG(@"findOffsets: il2cpp_domain_get_assemblies() returned NULL!");
        return;
    }
    LOG(@"findOffsets: found %zu assemblies", count);
    
    Il2CppImage* img = NULL;
    for (size_t i = 0; i < count; i++) {
        Il2CppImage* im = g_assembly_get_image(assemblies[i]);
        if (!im) continue;
        const char* n = g_image_get_name(im);
        if (n) {
            LOG(@"findOffsets: assembly[%zu] = %s", i, n);
            if (strcmp(n, "Assembly-CSharp.dll") == 0) {
                img = im;
                LOG(@"findOffsets: found Assembly-CSharp.dll!");
                break;
            }
        }
    }
    
    if (!img) {
        LOG(@"findOffsets: Assembly-CSharp.dll not found!");
        return;
    }
    
    Il2CppClass* bm = g_class_from_name(img, "", "BattleManager");
    if (!bm) {
        LOG(@"findOffsets: BattleManager class not found!");
        return;
    }
    LOG(@"findOffsets: BattleManager class = %p", bm);
    
    if (g_class_init) {
        g_class_init(bm);
        LOG(@"findOffsets: il2cpp_class_init(BattleManager) called");
    }
    
    if (g_class_get_static_data) {
        bm_static_data = g_class_get_static_data(bm);
        LOG(@"findOffsets: BattleManager static data = %p", bm_static_data);
    }
    
    FieldInfo* f;
    if ((f = g_class_get_field(bm, "m_ShowPlayers"))) {
        off_m_ShowPlayers = g_field_get_offset(f);
        LOG(@"findOffsets: m_ShowPlayers offset = 0x%zx", off_m_ShowPlayers);
    } else {
        LOG(@"findOffsets: m_ShowPlayers field not found!");
    }
    
    if ((f = g_class_get_field(bm, "ShowEntity"))) {
        off_ShowEntity = g_field_get_offset(f);
        LOG(@"findOffsets: ShowEntity offset = 0x%zx", off_ShowEntity);
    } else {
        LOG(@"findOffsets: ShowEntity field not found!");
    }
    
    if ((f = g_class_get_field(bm, "m_LocalPlayerShow"))) {
        off_m_LocalPlayerShow = g_field_get_offset(f);
        LOG(@"findOffsets: m_LocalPlayerShow offset = 0x%zx", off_m_LocalPlayerShow);
    } else {
        LOG(@"findOffsets: m_LocalPlayerShow field not found!");
    }
    
    LOG(@"findOffsets: complete!");
}

static void* workerThread(void* arg) {
    LOG(@"workerThread: started, waiting 10s for UnityFramework...");
    sleep(10);
    
    if (!loadIl2Cpp()) {
        LOG(@"workerThread: loadIl2Cpp() failed!");
        return NULL;
    }
    
    LOG(@"workerThread: trying to find offsets (5 attempts)...");
    for (int attempt = 0; attempt < 5 && g_running; attempt++) {
        LOG(@"workerThread: attempt %d/5", attempt + 1);
        findOffsets();
        
        if (bm_static_data && off_m_ShowPlayers > 0) {
            LOG(@"workerThread: offsets found! Starting main loop...");
            break;
        }
        
        LOG(@"workerThread: offsets not found yet, waiting 5s...");
        sleep(5);
    }
    
    if (!bm_static_data || off_m_ShowPlayers == 0) {
        LOG(@"workerThread: failed to find offsets after 5 attempts!");
        return NULL;
    }
    
    int write_count = 0;
    while (g_running) {
        if (bm_static_data && off_m_ShowPlayers > 0) {
            void* bm = *(void* volatile*)bm_static_data;
            
            if (bm && (uintptr_t)bm > 0x10000) {
                if (write_count % 10 == 0) {  // Log every 5 seconds
                    LOG(@"workerThread: BattleManager instance = %p, writing...", bm);
                }
                
                safeWrite((uint8_t*)bm + off_m_ShowPlayers, 1);
                if (off_ShowEntity > 0)        safeWrite((uint8_t*)bm + off_ShowEntity, 1);
                if (off_m_LocalPlayerShow > 0) safeWrite((uint8_t*)bm + off_m_LocalPlayerShow, 1);
                
                write_count++;
            } else {
                if (write_count % 10 == 0) {
                    LOG(@"workerThread: BattleManager instance is NULL (in lobby?)");
                }
            }
        }
        
        usleep(500000); // 500ms
    }
    
    LOG(@"workerThread: exiting");
    return NULL;
}

__attribute__((constructor))
static void maphack_init(void) {
    LOG(@"maphack_init: dylib loaded, starting worker thread...");
    pthread_create(&g_thread, NULL, workerThread, NULL);
    pthread_detach(g_thread);
    LOG(@"maphack_init: worker thread started");
}
