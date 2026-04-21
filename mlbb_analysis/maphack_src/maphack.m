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

// il2cpp types
typedef void* Il2CppDomain;
typedef void* Il2CppAssembly;
typedef void* Il2CppImage;
typedef void* Il2CppClass;
typedef void* FieldInfo;

typedef Il2CppDomain*    (*il2cpp_domain_get_t)(void);
typedef Il2CppAssembly** (*il2cpp_domain_get_assemblies_t)(Il2CppDomain* domain, size_t* size);
typedef Il2CppImage*     (*il2cpp_assembly_get_image_t)(Il2CppAssembly* assembly);
typedef const char*      (*il2cpp_image_get_name_t)(Il2CppImage* image);
typedef Il2CppClass*     (*il2cpp_class_from_name_t)(Il2CppImage* image, const char* ns, const char* name);
typedef FieldInfo*       (*il2cpp_class_get_field_from_name_t)(Il2CppClass* klass, const char* name);
typedef size_t           (*il2cpp_field_get_offset_t)(FieldInfo* field);
typedef void*            (*il2cpp_class_get_static_field_data_t)(Il2CppClass* klass);
typedef void             (*il2cpp_class_init_t)(Il2CppClass* klass);

static il2cpp_domain_get_t                  _domain_get;
static il2cpp_domain_get_assemblies_t       _domain_get_assemblies;
static il2cpp_assembly_get_image_t          _assembly_get_image;
static il2cpp_image_get_name_t              _image_get_name;
static il2cpp_class_from_name_t             _class_from_name;
static il2cpp_class_get_field_from_name_t   _class_get_field;
static il2cpp_field_get_offset_t            _field_get_offset;
static il2cpp_class_get_static_field_data_t _class_get_static_data;
static il2cpp_class_init_t                  _class_init;

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
    // Apply map hack every tick
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
    #define L(fn, sym) _##fn = (il2cpp_##fn##_t)dlsym(h, sym); if (!_##fn) return NO;
    L(domain_get,              "il2cpp_domain_get")
    L(domain_get_assemblies,   "il2cpp_domain_get_assemblies")
    L(assembly_get_image,      "il2cpp_assembly_get_image")
    L(image_get_name,          "il2cpp_image_get_name")
    L(class_from_name,         "il2cpp_class_from_name")
    L(class_get_field,         "il2cpp_class_get_field_from_name")
    L(field_get_offset,        "il2cpp_field_get_offset")
    L(class_get_static_data,   "il2cpp_class_get_static_field_data")
    L(class_init,              "il2cpp_class_init")
    #undef L
    return YES;
}

static void findOffsets(void) {
    Il2CppDomain* domain = _domain_get();
    if (!domain) return;
    size_t count = 0;
    Il2CppAssembly** assemblies = _domain_get_assemblies(domain, &count);
    if (!assemblies) return;
    Il2CppImage* img = NULL;
    for (size_t i = 0; i < count; i++) {
        Il2CppImage* im = _assembly_get_image(assemblies[i]);
        if (!im) continue;
        const char* n = _image_get_name(im);
        if (n && strcmp(n, "Assembly-CSharp.dll") == 0) { img = im; break; }
    }
    if (!img) { NSLog(@"[MapHack] Assembly-CSharp not found"); return; }
    Il2CppClass* bm = _class_from_name(img, "", "BattleManager");
    if (!bm) { NSLog(@"[MapHack] BattleManager not found"); return; }
    _class_init(bm);
    bm_static_data = _class_get_static_data(bm);
    FieldInfo* f;
    if ((f = _class_get_field(bm, "m_ShowPlayers")))     off_m_ShowPlayers     = _field_get_offset(f);
    if ((f = _class_get_field(bm, "ShowEntity")))        off_ShowEntity        = _field_get_offset(f);
    if ((f = _class_get_field(bm, "m_LocalPlayerShow"))) off_m_LocalPlayerShow = _field_get_offset(f);
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
