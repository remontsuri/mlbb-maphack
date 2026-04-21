/*
 * MLBB Map Hack - Non-jailbreak iOS
 * Uses il2cpp API + vm_remap (like Wraith)
 * NO UI overlay to avoid iOS 26.3 crashes
 */

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <string.h>
#include <mach/mach.h>

static BOOL safeWrite(void* addr, uint8_t val) {
    if (!addr || (uintptr_t)addr < 0x10000) return NO;
    vm_address_t newAddr = 0;
    vm_prot_t curProt, maxProt;
    kern_return_t kr = vm_remap(mach_task_self(), &newAddr, 1, 0, VM_FLAGS_ANYWHERE,
                                mach_task_self(), (vm_address_t)addr,
                                FALSE, &curProt, &maxProt, VM_INHERIT_SHARE);
    if (kr == KERN_SUCCESS) {
        *(uint8_t*)newAddr = val;
        vm_deallocate(mach_task_self(), newAddr, 1);
    } else {
        *(uint8_t*)addr = val;
    }
    return YES;
}

typedef void* Il2CppDomain;
typedef void* Il2CppAssembly;
typedef void* Il2CppImage;
typedef void* Il2CppClass;
typedef void* FieldInfo;

typedef Il2CppDomain*    (*fn_domain_get_t)(void);
typedef Il2CppAssembly** (*fn_domain_get_assemblies_t)(Il2CppDomain* domain, size_t* size);
typedef Il2CppImage*     (*fn_assembly_get_image_t)(Il2CppAssembly* assembly);
typedef const char*      (*fn_image_get_name_t)(Il2CppImage* image);
typedef Il2CppClass*     (*fn_class_from_name_t)(Il2CppImage* image, const char* ns, const char* name);
typedef FieldInfo*       (*fn_class_get_field_t)(Il2CppClass* klass, const char* name);
typedef size_t           (*fn_field_get_offset_t)(FieldInfo* field);
typedef void*            (*fn_class_get_static_data_t)(Il2CppClass* klass);
typedef void             (*fn_class_init_t)(Il2CppClass* klass);

static fn_domain_get_t            g_domain_get;
static fn_domain_get_assemblies_t g_domain_get_assemblies;
static fn_assembly_get_image_t    g_assembly_get_image;
static fn_image_get_name_t        g_image_get_name;
static fn_class_from_name_t       g_class_from_name;
static fn_class_get_field_t       g_class_get_field;
static fn_field_get_offset_t      g_field_get_offset;
static fn_class_get_static_data_t g_class_get_static_data;
static fn_class_init_t            g_class_init;

static size_t off_m_ShowPlayers     = 0;
static size_t off_ShowEntity        = 0;
static size_t off_m_LocalPlayerShow = 0;
static void*  bm_static_data        = NULL;
static NSTimer* g_timer             = nil;

static void tickMapHack(void) {
    if (bm_static_data && off_m_ShowPlayers > 0) {
        void* bm = *(void* volatile*)bm_static_data;
        if (bm && (uintptr_t)bm > 0x10000) {
            safeWrite((uint8_t*)bm + off_m_ShowPlayers, 1);
            if (off_ShowEntity > 0)        safeWrite((uint8_t*)bm + off_ShowEntity, 1);
            if (off_m_LocalPlayerShow > 0) safeWrite((uint8_t*)bm + off_m_LocalPlayerShow, 1);
        }
    }
}

static BOOL loadIl2Cpp(void) {
    const char* uf_path = NULL;
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char* name = _dyld_get_image_name(i);
        if (name && strstr(name, "UnityFramework")) { uf_path = name; break; }
    }
    if (!uf_path) return NO;
    void* h = dlopen(uf_path, RTLD_LAZY | RTLD_NOLOAD);
    if (!h) return NO;
    g_domain_get            = (fn_domain_get_t)dlsym(h, "il2cpp_domain_get");
    g_domain_get_assemblies = (fn_domain_get_assemblies_t)dlsym(h, "il2cpp_domain_get_assemblies");
    g_assembly_get_image    = (fn_assembly_get_image_t)dlsym(h, "il2cpp_assembly_get_image");
    g_image_get_name        = (fn_image_get_name_t)dlsym(h, "il2cpp_image_get_name");
    g_class_from_name       = (fn_class_from_name_t)dlsym(h, "il2cpp_class_from_name");
    g_class_get_field       = (fn_class_get_field_t)dlsym(h, "il2cpp_class_get_field_from_name");
    g_field_get_offset      = (fn_field_get_offset_t)dlsym(h, "il2cpp_field_get_offset");
    g_class_get_static_data = (fn_class_get_static_data_t)dlsym(h, "il2cpp_class_get_static_field_data");
    g_class_init            = (fn_class_init_t)dlsym(h, "il2cpp_class_init");
    return (g_domain_get && g_class_from_name) ? YES : NO;
}

static void findOffsets(void) {
    if (!g_domain_get) return;
    Il2CppDomain* domain = g_domain_get();
    if (!domain) return;
    size_t count = 0;
    Il2CppAssembly** assemblies = g_domain_get_assemblies(domain, &count);
    if (!assemblies) return;
    Il2CppImage* img = NULL;
    for (size_t i = 0; i < count; i++) {
        Il2CppImage* im = g_assembly_get_image(assemblies[i]);
        if (!im) continue;
        const char* n = g_image_get_name(im);
        if (n && strcmp(n, "Assembly-CSharp.dll") == 0) { img = im; break; }
    }
    if (!img) return;
    Il2CppClass* bm = g_class_from_name(img, "", "BattleManager");
    if (!bm) return;
    if (g_class_init) g_class_init(bm);
    if (g_class_get_static_data) bm_static_data = g_class_get_static_data(bm);
    FieldInfo* f;
    if ((f = g_class_get_field(bm, "m_ShowPlayers")))     off_m_ShowPlayers     = g_field_get_offset(f);
    if ((f = g_class_get_field(bm, "ShowEntity")))        off_ShowEntity        = g_field_get_offset(f);
    if ((f = g_class_get_field(bm, "m_LocalPlayerShow"))) off_m_LocalPlayerShow = g_field_get_offset(f);
}

static void startMapHack(void) {
    if (!loadIl2Cpp()) return;
    
    // Start background timer (no UI)
    g_timer = [NSTimer scheduledTimerWithTimeInterval:0.5
                                               target:[NSBlockOperation blockOperationWithBlock:^{ tickMapHack(); }]
                                             selector:@selector(main)
                                             userInfo:nil
                                              repeats:YES];
    
    // Try to find offsets multiple times
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ findOffsets(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 25 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ if (!bm_static_data) findOffsets(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ if (!bm_static_data) findOffsets(); });
}

__attribute__((constructor))
static void maphack_init(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        startMapHack();
    });
}
