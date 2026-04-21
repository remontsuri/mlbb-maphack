/*
 * MLBB Map Hack - Jailed iOS (no jailbreak required)
 * Uses il2cpp API + UIView overlay
 * No MSHookFunction, no substrate
 */

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <string.h>

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

static fn_domain_get_t          g_domain_get;
static fn_domain_get_assemblies_t g_domain_get_assemblies;
static fn_assembly_get_image_t  g_assembly_get_image;
static fn_image_get_name_t      g_image_get_name;
static fn_class_from_name_t     g_class_from_name;
static fn_class_get_field_t     g_class_get_field;
static fn_field_get_offset_t    g_field_get_offset;
static fn_class_get_static_data_t g_class_get_static_data;
static fn_class_init_t          g_class_init;

static size_t off_m_ShowPlayers     = 0;
static size_t off_ShowEntity        = 0;
static size_t off_m_LocalPlayerShow = 0;
static void*  bm_static_data        = NULL;

@interface MapHackView : UIView
@end

@implementation MapHackView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
        [NSTimer scheduledTimerWithTimeInterval:0.3 target:self selector:@selector(tick) userInfo:nil repeats:YES];
    }
    return self;
}

- (void)tick {
    if (bm_static_data) {
        void* bm = *(void**)bm_static_data;
        if (bm) {
            if (off_m_ShowPlayers)     *((uint8_t*)bm + off_m_ShowPlayers)     = 1;
            if (off_ShowEntity)        *((uint8_t*)bm + off_ShowEntity)         = 1;
            if (off_m_LocalPlayerShow) *((uint8_t*)bm + off_m_LocalPlayerShow) = 1;
        }
    }
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;
    BOOL active = (bm_static_data && *(void**)bm_static_data);
    UIColor* color = active ? [UIColor colorWithRed:0 green:1 blue:0 alpha:0.9]
                            : [UIColor colorWithRed:1 green:0 blue:0 alpha:0.9];
    CGContextSetFillColorWithColor(ctx, color.CGColor);
    CGContextFillEllipseInRect(ctx, CGRectMake(5, 10, 16, 16));
    NSDictionary* attrs = @{NSForegroundColorAttributeName: color,
                            NSFontAttributeName: [UIFont boldSystemFontOfSize:11]};
    NSString* label = active ? @"MAP ON" : @"MAP OFF";
    [label drawAtPoint:CGPointMake(26, 10) withAttributes:attrs];
}

@end

static BOOL loadIl2Cpp(void) {
    const char* uf_path = NULL;
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char* name = _dyld_get_image_name(i);
        if (name && strstr(name, "UnityFramework")) { uf_path = name; break; }
    }
    if (!uf_path) return NO;
    void* h = dlopen(uf_path, RTLD_LAZY | RTLD_NOLOAD);
    if (!h) return NO;

    g_domain_get              = (fn_domain_get_t)dlsym(h, "il2cpp_domain_get");
    g_domain_get_assemblies   = (fn_domain_get_assemblies_t)dlsym(h, "il2cpp_domain_get_assemblies");
    g_assembly_get_image      = (fn_assembly_get_image_t)dlsym(h, "il2cpp_assembly_get_image");
    g_image_get_name          = (fn_image_get_name_t)dlsym(h, "il2cpp_image_get_name");
    g_class_from_name         = (fn_class_from_name_t)dlsym(h, "il2cpp_class_from_name");
    g_class_get_field         = (fn_class_get_field_t)dlsym(h, "il2cpp_class_get_field_from_name");
    g_field_get_offset        = (fn_field_get_offset_t)dlsym(h, "il2cpp_field_get_offset");
    g_class_get_static_data   = (fn_class_get_static_data_t)dlsym(h, "il2cpp_class_get_static_field_data");
    g_class_init              = (fn_class_init_t)dlsym(h, "il2cpp_class_init");

    return (g_domain_get && g_class_from_name && g_class_get_field) ? YES : NO;
}

static void findOffsets(void) {
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
    if (!img) { NSLog(@"[MapHack] Assembly-CSharp not found"); return; }
    Il2CppClass* bm = g_class_from_name(img, "", "BattleManager");
    if (!bm) { NSLog(@"[MapHack] BattleManager not found"); return; }
    if (g_class_init) g_class_init(bm);
    if (g_class_get_static_data) bm_static_data = g_class_get_static_data(bm);
    FieldInfo* f;
    if ((f = g_class_get_field(bm, "m_ShowPlayers")))     off_m_ShowPlayers     = g_field_get_offset(f);
    if ((f = g_class_get_field(bm, "ShowEntity")))        off_ShowEntity        = g_field_get_offset(f);
    if ((f = g_class_get_field(bm, "m_LocalPlayerShow"))) off_m_LocalPlayerShow = g_field_get_offset(f);
    NSLog(@"[MapHack] BM=%p ShowPlayers=0x%zx ShowEntity=0x%zx Local=0x%zx",
          bm_static_data, off_m_ShowPlayers, off_ShowEntity, off_m_LocalPlayerShow);
}

static void startMapHack(void) {
    if (!loadIl2Cpp()) { NSLog(@"[MapHack] il2cpp load failed"); return; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 6 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        findOffsets();
        UIWindow* win = nil;
        for (UIScene* scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene* ws = (UIWindowScene*)scene;
                for (UIWindow* w in ws.windows) {
                    if (w.isKeyWindow) { win = w; break; }
                }
            }
            if (win) break;
        }
        if (!win) win = [UIApplication sharedApplication].windows.firstObject;
        if (!win) return;
        MapHackView* v = [[MapHackView alloc] initWithFrame:CGRectMake(10, 60, 100, 36)];
        v.layer.zPosition = 9999;
        [win addSubview:v];
        NSLog(@"[MapHack] Overlay added");
    });
}

__attribute__((constructor))
static void maphack_init(void) {
    NSLog(@"[MapHack] Loaded");
    dispatch_async(dispatch_get_main_queue(), ^{ startMapHack(); });
}
