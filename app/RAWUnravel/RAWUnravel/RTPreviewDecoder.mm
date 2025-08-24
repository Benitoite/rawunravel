/*
    RawUnravel - RTPreviewDecoder.mm
    --------------------------------
    Copyright (C) 2025 Richard Barber

    This file is part of RawUnravel.

    RawUnravel is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    RawUnravel is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with RawUnravel.  If not, see <https://www.gnu.org/licenses/>.
*/

// MARK: - Includes (keep existing ones)
#import "LibrtprocessBridge.h"
#import "librtprocess.h"
#import "RUShared.h"
#import "RTPreviewDecoder.h"
#import <UIKit/UIKit.h>
#import <ImageIO/ImageIO.h>
#import <libraw/libraw.h>
#import <algorithm>
#import <cmath>
#import <memory>
#import <Foundation/Foundation.h>
#include <CoreFoundation/CoreFoundation.h>
#include <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>
#include <cstdint>  // for uint8_t (or <stdint.h>)
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <ImageIO/ImageIO.h>
#include <limits>
#include <math.h>   // for logf/log2f

// Simple stickies keyed by (rawPath|jobID)
static NSMutableDictionary<NSString*, NSNumber*> *gRUStickyEV; // baseline EV per session/file
//static inline NSString* RU_EVKey(NSString *rawPath, NSString *jobID) {
//    return (jobID.length ? [rawPath stringByAppendingFormat:@"|%@", jobID] : rawPath);
//}
static inline bool RU_GetStickyEV_NS(NSString *key, float *outEV) {
    if (!key) return false;
    NSNumber *n = gRUStickyEV[key];
    if (!n) return false;
    if (outEV) *outEV = n.floatValue;
    return true;
}
static inline void RU_SetStickyEV_NS(NSString *key, float ev) {
    if (!key) return;
    if (!gRUStickyEV) gRUStickyEV = [NSMutableDictionary new];
    gRUStickyEV[key] = @(ev);
}

// Track the current decode’s key for BGRA helper path
static NSString *gRU_CurrentEVKey = nil;
// Map the p-th luminance percentile to `target` and return the EV needed.
// Does NOT modify R/G/B; works in linear.

static inline float RU_log2f(float x) { return logf(x)/logf(2.f); }

static float RU_AutoEVFromPercentile(const float *R, const float *G, const float *B,
                                     int N, float percentile, float target)
{
    if (N <= 0) return 0.f;
    const int BINS = 1024;
    int hist[BINS]; memset(hist, 0, sizeof(hist));

    for (int i=0;i<N;++i){
        float y = 0.2126f*R[i] + 0.7152f*G[i] + 0.0722f*B[i];
        y = std::clamp(y, 0.f, 1.f);
        int b = (int)floorf(y * (BINS-1));
        hist[b]++;
    }
    const int cutoff = (int)lrintf(std::clamp(percentile,0.f,1.f) * (float)N);
    int acc = 0, binIdx = BINS-1;
    for (int b=0; b<BINS; ++b){ acc += hist[b]; if (acc >= cutoff){ binIdx = b; break; } }
    float pY = (float)binIdx / (float)(BINS-1);
    if (pY <= 1e-6f) return 0.f;

    float k = std::clamp(target / pY, 0.25f, 8.0f); // same clamps as before
    return RU_log2f(k); // convert linear gain to EV
}
static inline int ru_safeIntSize(size_t n) {
    const size_t maxI = static_cast<size_t>(std::numeric_limits<int>::max());
    return static_cast<int>(n > maxI ? maxI : n);
}
static inline int RUFixPortraitEXIFIfBaked(CGImageRef cg, int exif) {
    if (!cg) return exif;
    const size_t w = CGImageGetWidth(cg);
    const size_t h = CGImageGetHeight(cg);
    if (exif == 3 && h > w) {
        return 1; // skip 180° for portrait previews that are already upright
    }
    return exif;
}

// Simple helper: checks if EXIF orientation implies a portrait frame
// w,h = pixel dimensions of the image (unrotated)
// exif = EXIF orientation (1..8)
static inline bool RUIsPortraitGivenEXIF(size_t w, size_t h, int exif) {
    // If EXIF rotates 90° or 270° then portrait-ness is swapped.
    bool rotated90 = (exif == 5 || exif == 6 || exif == 7 || exif == 8);
    if (rotated90) {
        return w > h;   // after rotation, width>height becomes portrait
    } else {
        return h > w;   // normal case
    }
}
// Normalize linear RGB so the p-th luminance percentile maps to `target`.
// Works in *linear* space. Cheap histogram, no allocs in hot path.
static void RU_NormalizeLumaPercentile(float *R, float *G, float *B, int N,
                                       float percentile /*0..1 e.g. 0.99f*/,
                                       float target /*0..1 e.g. 0.90f*/)
{
    if (N <= 0) return;
    const int BINS = 1024;
    int hist[BINS]; memset(hist, 0, sizeof(hist));

    // Build luminance histogram in linear
    for (int i=0;i<N;++i){
        float y = 0.2126f*R[i] + 0.7152f*G[i] + 0.0722f*B[i];
        if (y < 0.f) y = 0.f; if (y > 1.f) y = 1.f;
        int b = (int)floorf(y * (BINS-1));
        hist[b]++;
    }

    // Find percentile bin
    const int cutoff = (int)lrintf(std::clamp(percentile, 0.f, 1.f) * (float)N);
    int acc = 0, binIdx = BINS-1;
    for (int b=0; b<BINS; ++b){ acc += hist[b]; if (acc >= cutoff){ binIdx = b; break; } }

    const float pY = (float)binIdx / (float)(BINS-1);
    if (pY <= 1e-6f) return;

    // Scale so pY -> target (clamp gain a bit to avoid insanity)
    float k = target / pY;
    k = std::clamp(k, 0.25f, 8.0f);
    for (int i=0;i<N;++i){ R[i]*=k; G[i]*=k; B[i]*=k; }
}
// --- RLD progress callback + prototypes ---
typedef void (^RU_RLDProgressBlock)(int iter, int total);

// ru_gauss_blur is defined later; declare it so we can call it now.
static void ru_gauss_blur(float* buf, float* tmp, int W, int H, float radius);

// Progress variant; full body can live further down if you prefer.
static void RU_RLD_Luma_Linear_WithProgress(float *R, float *G, float *B,
                                            int W, int H,
                                            int iterations, float radius,
                                            float amountPct, float dampingPct,
                                            RU_RLDProgressBlock progress);
// Add at the top of RTPreviewDecoder.mm (ObjC++ file):
typedef void (^RU_RLDIterBlock)(int iter /*1-based*/, int total,
                                const float *gain /*length=W*H*/);

// New helper that calls a callback each iteration.
// It mutates E only; R/G/B are not touched here.
// Caller can build a preview by applying `gain` to base R/G/B.
static void RU_RLD_Luma_Linear_CB(const float *baseR, const float *baseG, const float *baseB,
                                  int W, int H,
                                  int iterations, float radius,
                                  float amountPct, float dampingPct,
                                  RU_RLDIterBlock cb)
{
    if (iterations <= 0 || amountPct <= 0.f || radius <= 0.05f) return;

    const int N = W*H;
    std::unique_ptr<float[]> Y (new float[N]);
    std::unique_ptr<float[]> E (new float[N]);
    std::unique_ptr<float[]> tmp(new float[N]);
    std::unique_ptr<float[]> buf(new float[N]);
    std::unique_ptr<float[]> gain(new float[N]);

    // Build initial luminance from base (linear)
    for (int i=0;i<N;++i) {
        float y = 0.2126f*baseR[i] + 0.7152f*baseG[i] + 0.0722f*baseB[i];
        Y[i] = std::clamp(y, 0.f, 1.f);
        E[i] = Y[i];
    }

    const float eps  = 1e-6f;
    const float kAmt = std::min(2.f, amountPct/100.f);          // 0..2
    const float damp = std::clamp(dampingPct/100.f, 0.f, 0.99f);
    const float rMin = 1.f - damp, rMax = 1.f + damp;

    auto gauss = [&](float *bufp){ ru_gauss_blur(bufp, tmp.get(), W, H, radius); };

    for (int t=0; t<iterations; ++t) {
        // blurred = PSF * E
        memcpy(buf.get(), E.get(), N*sizeof(float));
        gauss(buf.get());

        // ratio = Y / blurred (clamped by damping)
        for (int i=0;i<N;++i) {
            float ratio = Y[i] / (buf[i] + eps);
            if (damp>0.f) ratio = std::clamp(ratio, rMin, rMax);
            tmp[i] = ratio;
        }

        // correction = PSF^T * ratio  (PSF symmetric)
        memcpy(buf.get(), tmp.get(), N*sizeof(float));
        gauss(buf.get());

        // E *= correction
        for (int i=0;i<N;++i) E[i] = std::clamp(E[i] * buf[i], 0.f, 1.f);

        // Compute preview gain and notify
        if (cb) {
            for (int i=0;i<N;++i) {
                float g = E[i] / (Y[i] + eps);
                g = 1.f + (g - 1.f) * kAmt;    // blend by amount
                gain[i] = std::clamp(g, 0.f, 4.f);
            }
            cb(t+1, iterations, gain.get());   // 1-based iter
        }
    }
}
// Forward decl so we can call it before its definition
static void RU_ApplyPreviewSharpen_OnBGRA(uint8_t *bgra, int W, int H,
                                          int iters, float radius, float amount, float dampPct);

static void RU_RLD_Luma_Linear(float *R, float *G, float *B,
                               int W, int H,
                               int iterations, float radius,
                               float amountPct, float dampingPct);
// Local-only; no external symbol emitted.

extern "C" {

// EXIF from largest embedded preview
int RUExifOrientationFromLargestPreviewC(const char *pathC) {
    if (!pathC) return 1;

    CFStringRef cfPath = CFStringCreateWithCString(kCFAllocatorDefault, pathC, kCFStringEncodingUTF8);
    if (!cfPath) return 1;

    CFURLRef url = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, cfPath, kCFURLPOSIXPathStyle, false);
    CFRelease(cfPath);
    if (!url) return 1;

    CGImageSourceRef src = CGImageSourceCreateWithURL(url, /*options*/ NULL);
    CFRelease(url);
    if (!src) return 1;

    size_t count = CGImageSourceGetCount(src);
    int bestIndex = -1; long bestArea = -1;

    for (size_t i=0;i<count;++i) {
        CFDictionaryRef props = CGImageSourceCopyPropertiesAtIndex(src, i, NULL);
        if (!props) continue;
        int w=0,h=0;
        CFNumberRef wN=(CFNumberRef)CFDictionaryGetValue(props, kCGImagePropertyPixelWidth);
        CFNumberRef hN=(CFNumberRef)CFDictionaryGetValue(props, kCGImagePropertyPixelHeight);
        if (wN && hN) {
            CFNumberGetValue(wN, kCFNumberIntType, &w);
            CFNumberGetValue(hN, kCFNumberIntType, &h);
        }
        CFRelease(props);
        long area=(long)w*(long)h;
        if (w>0 && h>0 && area>bestArea) { bestArea=area; bestIndex=(int)i; }
    }

    int exif = 1;
    if (bestIndex >= 0) {
        CFDictionaryRef props = CGImageSourceCopyPropertiesAtIndex(src, bestIndex, NULL);
        if (props) {
            CFNumberRef n = (CFNumberRef)CFDictionaryGetValue(props, kCGImagePropertyOrientation);
            if (n) CFNumberGetValue(n, kCFNumberIntType, &exif);
            CFRelease(props);
        }
    }
    CFRelease(src);
    return exif;
}

// EXIF from file container root (index 0)
int RUExifOrientationFromFileC(const char *pathC) {
    if (!pathC) return 1;

    CFStringRef cfPath = CFStringCreateWithCString(kCFAllocatorDefault, pathC, kCFStringEncodingUTF8);
    if (!cfPath) return 1;

    CFURLRef url = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, cfPath, kCFURLPOSIXPathStyle, false);
    CFRelease(cfPath);
    if (!url) return 1;

    CGImageSourceRef src = CGImageSourceCreateWithURL(url, NULL);
    CFRelease(url);
    if (!src) return 1;

    int exif = 1;
    CFDictionaryRef props = CGImageSourceCopyPropertiesAtIndex(src, 0, NULL);
    if (props) {
        CFNumberRef n = (CFNumberRef)CFDictionaryGetValue(props, kCGImagePropertyOrientation);
        if (n) CFNumberGetValue(n, kCFNumberIntType, &exif);
        CFRelease(props);
    }
    CFRelease(src);
    return exif;
}

} // extern "C"

static CGImageRef RUCreateCGImageApplyingEXIF_KnownGood(CGImageRef inCG, int exif)
{
    if (!inCG || exif == 1) return inCG ? CGImageRetain(inCG) : NULL;

    CIImage *ci = [CIImage imageWithCGImage:inCG];
    // CGImagePropertyOrientation uses the exact TIFF/EXIF 1..8 values
    ci = [ci imageByApplyingOrientation:(CGImagePropertyOrientation)exif];

    static CIContext *ctx;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ ctx = [CIContext contextWithOptions:nil]; });

    CGImageRef outCG = [ctx createCGImage:ci fromRect:ci.extent];
    return outCG; // caller releases
}
// Exported, non-static wrapper so Swift/ObjC can call it.
extern "C" CGImageRef RUCreateCGImageApplyingEXIF(CGImageRef inCG, int exif) {
    return RUCreateCGImageApplyingEXIF_KnownGood(inCG, exif);
}

static inline UIImage *RUApplyFinalOrientation(UIImage *ui, int exif)
{
    if (!ui || exif == 1) return ui;
    CGImageRef cg = ui.CGImage; if (!cg) return ui;

    CGImageRef rot = RUCreateCGImageApplyingEXIF(cg, exif);
    if (!rot) return ui;

    UIImage *out = [UIImage imageWithCGImage:rot
                                       scale:ui.scale
                                 orientation:UIImageOrientationUp];
    CGImageRelease(rot);
    return out;
}

extern "C" {
int bridge_amaze_demosaic(const float *mono, int W, int H,
                          const unsigned *cfarray2x2, float *R, float *G, float *B);
int bridge_xtrans_demosaic(const float *P0, const float *P1, const float *P2,
                           int W, int H, const unsigned xtrans[6][6],
                           float *R, float *G, float *B);
}
static inline void buildCamToSRGB(const libraw_colordata_t &C, float M[9]) {
    const float *cx=C.cam_xyz[0], *cy=C.cam_xyz[1], *cz=C.cam_xyz[2];
    const float cam2xyz[9] = { cx[0],cx[1],cx[2],  cy[0],cy[1],cy[2],  cz[0],cz[1],cz[2] };
    const float xyz2srgb[9] = {
         3.2404542f, -1.5371385f, -0.4985314f,
        -0.9692660f,  1.8760108f,  0.0415560f,
         0.0556434f, -0.2040259f,  1.0572252f
    };
    for (int r=0;r<3;++r)
        for (int c=0;c<3;++c)
            M[3*r+c] = xyz2srgb[3*r+0]*cam2xyz[0*3+c]
                     + xyz2srgb[3*r+1]*cam2xyz[1*3+c]
                     + xyz2srgb[3*r+2]*cam2xyz[2*3+c];
    
}

static inline void mul3x3(const float M[9], float r,float g,float b, float &ro,float &go,float &bo){
    ro=M[0]*r+M[1]*g+M[2]*b;
    go=M[3]*r+M[4]*g+M[5]*b;
    bo=M[6]*r+M[7]*g+M[8]*b;
}
static inline void derive_cfarray_from_filters(const libraw_data_t *raw, unsigned out4[4]) {
    // RGGB as sensible default
    out4[0]=0; out4[1]=1; out4[2]=1; out4[3]=2;
    if (!raw || raw->idata.filters==0) return;

    // LibRaw packs Bayer filters in a 32-bit pattern. The low two bits are the color at (0,0).
    // Colors: 0=R, 1=G, 2=B (LibRaw internal)
    unsigned f = raw->idata.filters;
    auto colorAt = [&](int x, int y)->unsigned {
        return (f >> ((y&1)*2 + ((x&1)<<1))) & 3U;
    };
    out4[0] = colorAt(0,0);
    out4[1] = colorAt(1,0);
    out4[2] = colorAt(0,1);
    out4[3] = colorAt(1,1);
}
// ==== EXIF orientation helpers (define once in a .mm that is part of the target) ====

// One and only definition. Put this in a .mm that’s compiled into the target.
#import <CoreImage/CoreImage.h>

// MARK: - Forward decls you might already have

inline int RUMapLibRawFlipToEXIF(int librawFlip);
inline int RUMapLibRawFlipToEXIF(int flip) {
    switch (flip) {
        case 0: return 1; // none
        case 1: return 2; // mirror H
        case 2: return 4; // mirror V
        case 3: return 3; // 180
        case 4: return 5; // mirror + 90 CW (transpose)
        case 5: return 6; // 90 CW   ← was 8
        case 6: return 8; // 90 CCW  ← was 6
        case 7: return 7; // mirror + 90 CCW (transverse)
        default:return 1;
    }
}
void PostProgress(NSString *jobID, NSString *phase, NSString *step,
                                NSInteger iter=0, NSInteger total=0);

// If you don’t have a file EXIF orientation helper, here’s a tiny one:

// Minimal embedded-preview extractor used in fallback paths
static UIImage *RUEmbeddedPreviewUIImageAtPath(NSString *path) {
    NSURL *u = [NSURL fileURLWithPath:path];
    CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)u,
                                                      (__bridge CFDictionaryRef)@{(id)kCGImageSourceShouldCache:@NO});
    if (!src) return nil;
    size_t count = CGImageSourceGetCount(src);
    int bestIndex = -1; long bestArea = -1;
    for (size_t i=0;i<count;++i) {
        CFDictionaryRef props = CGImageSourceCopyPropertiesAtIndex(src, i, NULL);
        if (!props) continue;
        int w=0,h=0;
        CFNumberRef wN=(CFNumberRef)CFDictionaryGetValue(props, kCGImagePropertyPixelWidth);
        CFNumberRef hN=(CFNumberRef)CFDictionaryGetValue(props, kCGImagePropertyPixelHeight);
        if (wN && hN) { CFNumberGetValue(wN,kCFNumberIntType,&w); CFNumberGetValue(hN,kCFNumberIntType,&h); }
        CFRelease(props);
        long area=(long)w*(long)h;
        if (w>0 && h>0 && area>bestArea) { bestArea=area; bestIndex=(int)i; }
    }
    if (bestIndex<0) { CFRelease(src); return nil; }

    int exif=1;
    CFDictionaryRef props = CGImageSourceCopyPropertiesAtIndex(src, bestIndex, NULL);
    if (props) {
        CFNumberRef n = (CFNumberRef)CFDictionaryGetValue(props, kCGImagePropertyOrientation);
        if (n) CFNumberGetValue(n, kCFNumberIntType, &exif);
        CFRelease(props);
    }
    CGImageRef cg = CGImageSourceCreateImageAtIndex(src, bestIndex, NULL);
    CFRelease(src);
    if (!cg) return nil;
    UIImage *tmp = [UIImage imageWithCGImage:cg scale:1.0 orientation:UIImageOrientationUp];
    CGImageRelease(cg);
    if (exif==1) return tmp;
    CGImageRef rot = RUCreateCGImageApplyingEXIF_KnownGood(tmp.CGImage, exif);
    UIImage *out = [UIImage imageWithCGImage:rot scale:1.0 orientation:UIImageOrientationUp];
    CGImageRelease(rot);
    return out;
}

// =================== PP3 parsing ===================
struct RU_PP3 {
    bool  hasExposure=false;   float exposureEV=0.f;   // stops
    bool  hasBlack=false;      float black=0.f;        // 0..1 linear
    bool  hasShadows=false;    float shadows=0.f;      // -100..+100

    bool  chromaEnabled=false; float chromaticity=0.f; // %
    bool  cChromaEnabled=false;float cChroma=0.f;      // %
    bool  jContrastEnabled=false; float jContrast=0.f; // %

    int   deconvIter=0;        float deconvAmount=0.f; float deconvRadius=0.8f; float deconvDamping=0.f;
};
static inline bool RU_UserSetExposure(const RU_PP3& P) {
    // treat tiny EV as "no user exposure", keep auto-normalize on
    return P.hasExposure && fabsf(P.exposureEV) > 1e-4f;
}
static inline std::string ru_trim(const std::string& s){
    size_t a=s.find_first_not_of(" \t\r\n"), b=s.find_last_not_of(" \t\r\n");
    if (a==std::string::npos) return {}; return s.substr(a,b-a+1);
}

static bool RU_LoadPP3(const char* path, RU_PP3& P){
    if (!path || !*path) return false;
    FILE* f=fopen(path,"rb"); if(!f) return false;
    char line[512]; bool inLum=false, inCA=false;
    while (fgets(line,sizeof(line),f)){
        std::string s=ru_trim(line); if (s.empty()||s[0]=='#') continue;
        if (s[0]=='['){ inLum=(s.find("[Luminance Curve]")!=std::string::npos);
                        inCA =(s.find("[Color appearance]")!=std::string::npos); continue; }
        auto eq=s.find('='); if (eq==std::string::npos) continue;
        std::string k=ru_trim(s.substr(0,eq)), v=ru_trim(s.substr(eq+1));
        if (k=="Compensation"||k=="Exposure"||k=="ExposureCompensation"){
            P.exposureEV = strtof(v.c_str(),nullptr);
            P.hasExposure = (fabsf(P.exposureEV) > 1e-4f);
        }
        else if (k=="Black"||k=="BlackPoint"){ P.hasBlack=true; P.black=strtof(v.c_str(),nullptr)/255.f; }
        else if (k=="Shadows"){ P.hasShadows=true; P.shadows=strtof(v.c_str(),nullptr); }
        else if (inLum && k=="Chromaticity"){ P.chromaticity=strtof(v.c_str(),nullptr); P.chromaEnabled=true; }
        else if (inLum && k=="Enabled"){ P.chromaEnabled=(v=="true"||v=="1"); }
        else if (inCA && (k=="C-Chroma"||k=="CChroma")){ P.cChroma=strtof(v.c_str(),nullptr); }
        else if (inCA && (k=="C-ChromaEnabled"||k=="CChromaEnabled")){ P.cChromaEnabled=(v=="true"||v=="1"); }
        else if (inCA && (k=="J-Contrast"||k=="JContrast")){ P.jContrast=strtof(v.c_str(),nullptr); }
        else if (inCA && (k=="J-ContrastEnabled"||k=="JContrastEnabled")){ P.jContrastEnabled=(v=="true"||v=="1"); }
        else if (k=="DeconvIterations"||k=="RLDeconvIterations"){ P.deconvIter=(int)strtol(v.c_str(),nullptr,10); }
        else if (k=="DeconvAmount"){ P.deconvAmount=strtof(v.c_str(),nullptr); }
        else if (k=="DeconvRadius"){ P.deconvRadius=strtof(v.c_str(),nullptr); }
        else if (k=="DeconvDamping"){ P.deconvDamping=strtof(v.c_str(),nullptr); }
    }
    fclose(f); return true;
}
static inline bool RU_ShouldSharpen(const RU_PP3& P) {
    return (P.deconvIter > 0) && (P.deconvAmount > 0.f) && (P.deconvRadius > 0.f);
}
// =================== Color helpers (sRGB/XYZ/Lab) ===================
static inline float srgb_to_linear(float c){ return (c<=0.04045f)? c/12.92f : powf((c+0.055f)/1.055f,2.4f); }
static inline float linear_to_srgb(float c){ return (c<=0.0031308f)? 12.92f*c : 1.055f*powf(c,1.f/2.4f)-0.055f; }

static void rgb2xyz(float r,float g,float b,float*X,float*Y,float*Z){
    r=srgb_to_linear(r); g=srgb_to_linear(g); b=srgb_to_linear(b);
    *X = r*0.4124564f + g*0.3575761f + b*0.1804375f;
    *Y = r*0.2126729f + g*0.7151522f + b*0.0721750f;
    *Z = r*0.0193339f + g*0.1191920f + b*0.9503041f;
}
static void xyz2lab(float X,float Y,float Z,float*L,float*a,float*b){
    float Xr=0.95047f,Yr=1.f,Zr=1.08883f;
    auto f=[](float t){return t>0.008856f? powf(t,1.f/3.f): (7.787f*t + 16.f/116.f);};
    float fx=f(X/Xr), fy=f(Y/Yr), fz=f(Z/Zr);
    *L=116.f*fy-16.f; *a=500.f*(fx-fy); *b=200.f*(fy-fz);
}
static void lab2xyz(float L,float a,float b,float*X,float*Y,float*Z){
    float Xr=0.95047f,Yr=1.f,Zr=1.08883f;
    float fy=(L+16.f)/116.f, fx=fy + a/500.f, fz=fy - b/200.f;
    auto f3=[](float t){return t>0.206893f? t*t*t : (t-16.f/116.f)/7.787f;};
    *X=Xr*f3(fx); *Y=Yr*f3(fy); *Z=Zr*f3(fz);
}
static void xyz2rgb(float X,float Y,float Z,float*r,float*g,float*b){
    float rl =  3.2404542f*X -1.5371385f*Y -0.4985314f*Z;
    float gl = -0.9692660f*X +1.8760108f*Y +0.0415560f*Z;
    float bl =  0.0556434f*X -0.2040259f*Y +1.0572252f*Z;
    *r=linear_to_srgb(rl); *g=linear_to_srgb(gl); *b=linear_to_srgb(bl);
}

// =================== Linear-stage ops + preview sharpen ===================
static void RU_ApplyExposureEV(float *R,float *G,float *B,int N,float ev){
    if (fabsf(ev)<1e-6f) return; float k=powf(2.f,ev);
    for(int i=0;i<N;++i){ R[i]*=k; G[i]*=k; B[i]*=k; }
}
static void RU_ApplyBlack(float *R,float *G,float *B,int N,float bp){
    if (bp<=0.f) return; bp=std::min(bp,0.95f); float s=1.f/(1.f-bp);
    for(int i=0;i<N;++i){ R[i]=std::max(0.f,(R[i]-bp))*s; G[i]=std::max(0.f,(G[i]-bp))*s; B[i]=std::max(0.f,(B[i]-bp))*s; }
}
static void RU_ApplyShadows(float *R,float *G,float *B,int N,float sh){
    if (fabsf(sh)<1e-4f) return; float s=sh/100.f;
    for(int i=0;i<N;++i){
        auto op=[&](float x){ x=std::clamp(x,0.f,1.f); float Y=x; float lift=s*(1.f-Y)*Y; return std::clamp(x+lift,0.f,1.f); };
        R[i]=op(R[i]); G[i]=op(G[i]); B[i]=op(B[i]);
    }
}

// Cheap iterative blur/unsharp to preview “RLD”
static void RU_ApplyPreviewSharpen(float *R,float *G,float *B,int W,int H,int iters,float radius,float amount,float dampPct){
    if (iters<=0 || amount<=0.f || radius<=0.2f) return;
    const int N=W*H; const float k=amount/100.f; const float damp=std::clamp(dampPct/100.f,0.f,0.95f);
    std::unique_ptr<float[]> tmp(new float[N]);

    auto blur3 = [&](float *C){
        int r=std::max(1,(int)lrintf(radius));
        for(int p=0;p<r;++p){
            for(int y=0;y<H;++y){ float prev=C[y*W+0];
                for(int x=0;x<W;++x){ int i=y*W+x; float cur=C[i]; float nxt=(x+1<W)?C[i+1]:cur; tmp[i]=(prev+cur+nxt)/3.f; prev=cur; } }
            for(int x=0;x<W;++x){ float prev=tmp[0*W+x];
                for(int y=0;y<H;++y){ int i=y*W+x; float cur=tmp[i]; float nxt=(y+1<H)?tmp[i+W]:cur; C[i]=(prev+cur+nxt)/3.f; prev=cur; } }
        }
    };
    auto iterCh = [&](float *C){
        std::unique_ptr<float[]> base(new float[N]); memcpy(base.get(),C,N*sizeof(float));
        for(int t=0;t<iters;++t){
            std::unique_ptr<float[]> bl(new float[N]); memcpy(bl.get(),C,N*sizeof(float)); blur3(bl.get());
            for(int i=0;i<N;++i){
                float edge = base[i]-bl[i];
                float v = std::clamp(C[i] + k*edge, 0.f, 1.f);
                C[i] = v*(1.f-damp) + base[i]*damp;
            }
        }
    };
    iterCh(R); iterCh(G); iterCh(B);
}

// =================== Lab tweaks on 8-bit buffer (preview only) ===================
static void RU_ApplyLabOps_OnBGRA(uint8_t *bgra, int W, int H,
                                  bool chromaEnabled, float chromaticity,
                                  bool cChromaEnabled, float cChroma,
                                  bool jContrastEnabled, float jContrast)
{
    
    if (!(chromaEnabled || cChromaEnabled || jContrastEnabled)) return;
    const int N=W*H;
    for (int i=0;i<N;++i){
        uint8_t B=bgra[i*4+0], G=bgra[i*4+1], R=bgra[i*4+2];
        float r=R/255.f, g=G/255.f, b=B/255.f;
        float X,Y,Z,L,a,b2; rgb2xyz(r,g,b,&X,&Y,&Z); xyz2lab(X,Y,Z,&L,&a,&b2);

        if (chromaEnabled && fabsf(chromaticity)>0.01f){
            float m=1.f + chromaticity/100.f; a*=m; b2*=m;
        }
        if (cChromaEnabled && fabsf(cChroma)>0.01f){
            float m=1.f + cChroma/100.f; float C=hypotf(a,b2), ang=atan2f(b2,a);
            C*=m; a=C*cosf(ang); b2=C*sinf(ang);
        }
        if (jContrastEnabled && fabsf(jContrast)>0.01f){
            float m=1.f + jContrast/100.f; L=(L-50.f)*m + 50.f; L=std::clamp(L,0.f,100.f);
        }

        lab2xyz(L,a,b2,&X,&Y,&Z); xyz2rgb(X,Y,Z,&r,&g,&b);
        r=std::clamp(r,0.f,1.f); g=std::clamp(g,0.f,1.f); b=std::clamp(b,0.f,1.f);
        bgra[i*4+0]=(uint8_t)lrintf(b*255.f);
        bgra[i*4+1]=(uint8_t)lrintf(g*255.f);
        bgra[i*4+2]=(uint8_t)lrintf(r*255.f);
    }
}
static void RU_ApplyToneOps_OnBGRA(uint8_t *bgra, int W, int H, const RU_PP3 &P);
// =================== Implementation ===================
@implementation RTPreviewDecoder

+ (nullable UIImage *)decodeRAWPreviewAtPath:(NSString *)rawPath
                                 withPP3Path:(NSString *)pp3Path
                                    halfSize:(BOOL)halfSize
                                       jobID:(NSString *)jobID
{
    NSLog(@"[RTPreviewDecoder] decodePreview half=%d path=%@", halfSize, rawPath);
    if (!rawPath || rawPath.length==0) return nil;
    if (![[NSFileManager defaultManager] fileExistsAtPath:rawPath]) return nil;

    return halfSize
        ? [self halfSizeSuperpixelAtPath:rawPath pp3Path:pp3Path jobID:jobID]
        : [self fullResAMAZEAtPath:rawPath pp3Path:pp3Path jobID:jobID];
}

static inline float ru_srgb_to_linear(float c){ return (c<=0.04045f)? c/12.92f : powf((c+0.055f)/1.055f, 2.4f); }
static inline float ru_linear_to_srgb(float c){
    // keep numerically safe and clamp at the end
    if (c <= 0.0031308f) return 12.92f * c;
    return 1.055f * powf(fmaxf(c, 0.f), 1.f/2.4f) - 0.055f;
}

// Applies PP3 exposure/black/shadows in *linear* space to a BGRA8 buffer
static void RU_ApplyToneOps_OnBGRA(uint8_t *bgra, int W, int H, const RU_PP3 &P)
{
    const int N = W * H;
    if (!(P.hasExposure || P.hasBlack || P.hasShadows)) return;

    // 1) BGRA -> linear float planes
    std::unique_ptr<float[]> R(new float[N]), G(new float[N]), B(new float[N]);
    for (int i = 0; i < N; ++i) {
        const float r = bgra[i*4 + 2] / 255.f;
        const float g = bgra[i*4 + 1] / 255.f;
        const float b = bgra[i*4 + 0] / 255.f;
        R[i] = ru_srgb_to_linear(r);
        G[i] = ru_srgb_to_linear(g);
        B[i] = ru_srgb_to_linear(b);
    }

    // 2) Exposure (in stops)
    if (P.hasExposure) {
        const float k = powf(2.f, P.exposureEV);
        for (int i = 0; i < N; ++i) { R[i] *= k; G[i] *= k; B[i] *= k; }
    }

    // 3) Black point lift (normalize range)
    if (P.hasBlack) {
        float bp = fminf(fmaxf(P.black, 0.f), 0.95f);
        const float s = 1.f / (1.f - bp);
        for (int i = 0; i < N; ++i) {
            R[i] = fmaxf(0.f, R[i] - bp) * s;
            G[i] = fmaxf(0.f, G[i] - bp) * s;
            B[i] = fmaxf(0.f, B[i] - bp) * s;
        }
    }

    // 4) Shadows lift (simple perceptual lift)
    if (P.hasShadows) {
        const float s = P.shadows / 100.f;
        for (int i = 0; i < N; ++i) {
            auto lift = [&](float x){
                x = fminf(fmaxf(x, 0.f), 1.f);
                const float Y = x;
                return fminf(fmaxf(x + s * (1.f - Y) * Y, 0.f), 1.f);
            };
            R[i] = lift(R[i]); G[i] = lift(G[i]); B[i] = lift(B[i]);
        }
    }

    
    // 5) Back to sRGB into BGRA
    for (int i = 0; i < N; ++i) {
        const float r = fminf(fmaxf(ru_linear_to_srgb(R[i]), 0.f), 1.f);
        const float g = fminf(fmaxf(ru_linear_to_srgb(G[i]), 0.f), 1.f);
        const float b = fminf(fmaxf(ru_linear_to_srgb(B[i]), 0.f), 1.f);
        bgra[i*4 + 2] = (uint8_t)lrintf(r * 255.f);
        bgra[i*4 + 1] = (uint8_t)lrintf(g * 255.f);
        bgra[i*4 + 0] = (uint8_t)lrintf(b * 255.f);
        // alpha (i*4+3) untouched
    }
}
static inline NSString* RU_EVKey(NSString *rawPath, NSString *jobID) {
    return (jobID.length ? [rawPath stringByAppendingFormat:@"|%@", jobID] : rawPath);
}

// Full-res (AMAZE) → linear sRGB → PP3 linear ops → preview sharpen → pack BGRA → Lab ops → orient
+ (nullable UIImage *)fullResAMAZEAtPath:(NSString *)rawPath
                                 pp3Path:(NSString *)pp3Path
                                   jobID:(nullable NSString *)jobID
{
    @autoreleasepool {
        if (!rawPath || rawPath.length==0) return nil;
        if (![[NSFileManager defaultManager] fileExistsAtPath:rawPath]) return RUEmbeddedPreviewUIImageAtPath(rawPath);
   
        // Load PP3 (if any)
        RU_PP3 P; RU_LoadPP3(pp3Path.length? pp3Path.UTF8String:NULL, P);
        NSLog(@"[PP3] iter=%d amount=%.1f radius=%.3f damp=%.1f",
              P.deconvIter, P.deconvAmount, P.deconvRadius, P.deconvDamping);
        
        PostProgress(jobID, @"libraw", @"open");
        libraw_data_t *raw = libraw_init(0);
        if (!raw) return RUEmbeddedPreviewUIImageAtPath(rawPath);

        if (libraw_open_file(raw, rawPath.UTF8String) != LIBRAW_SUCCESS) {
            libraw_close(raw); return RUEmbeddedPreviewUIImageAtPath(rawPath);
        }
        // after libraw_unpack(raw) == LIBRAW_SUCCESS
        const int flipEXIF = RUMapLibRawFlipToEXIF(raw->sizes.flip);
        PostProgress(jobID, @"libraw", @"identify");
     

        const int W = raw->sizes.iwidth, H = raw->sizes.iheight, N = W*H;

        if (libraw_unpack(raw) != LIBRAW_SUCCESS) {
            libraw_close(raw); return RUEmbeddedPreviewUIImageAtPath(rawPath);
        }
        PostProgress(jobID, @"libraw", @"unpack");

        std::unique_ptr<float[]> R(new float[N]), G(new float[N]), B(new float[N]);
        bool demosaicOK = false;
        PostProgress(jobID, @"libraw", @"demosaic");
        if (raw->idata.filters != 0 && raw->rawdata.raw_image) {
            // ---- Bayer path (AMAZE) ----
            const uint16_t *mosaic = raw->rawdata.raw_image;
            unsigned cf4[4]; derive_cfarray_from_filters(raw, cf4);

            // Per-channel black, fallback to global
            const float white = (float)raw->color.maximum;
            float blackGlobal = (float)raw->color.black; if (!(blackGlobal>0.f)) blackGlobal = 0.f;

            int cbl[4] = {
                (int)raw->color.cblack[0], (int)raw->color.cblack[1],
                (int)raw->color.cblack[2], (int)raw->color.cblack[3]
            };
            for (int k=0;k<4;k++) if (cbl[k] <= 0) cbl[k] = (int)blackGlobal;

            std::unique_ptr<float[]> mono(new float[N]);
            for (int y=0; y<H; ++y) for (int x=0; x<W; ++x) {
                const int i = y*W + x;
                const int ch = cf4[((y&1)<<1)|(x&1)];
                const float v = (float)mosaic[i] - (float)cbl[ch];
                const float d = std::max(1.0f, white - (float)cbl[ch]);
                mono[i] = v > 0 ? (v / d) : 0.0f;   // 0..1
            }
            demosaicOK = (bridge_amaze_demosaic(mono.get(), W, H, cf4, R.get(), G.get(), B.get()) == 0);

        } else if (raw->rawdata.color3_image) {
            // ---- X-Trans path ----
            const uint16_t (*ximg)[3] = raw->rawdata.color3_image;
            const float white = (float)raw->color.maximum;
            float blackGlobal = (float)raw->color.black; if (!(blackGlobal>0.f)) blackGlobal=0.f;
            const float denom = std::max(1.0f, white - blackGlobal);

            std::unique_ptr<float[]> P0(new float[N]), P1(new float[N]), P2(new float[N]);
            for (int y=0; y<H; ++y) {
                const uint16_t (*row)[3] = &ximg[y*(size_t)W];
                for (int x=0; x<W; ++x) {
                    const int i = y*W + x;
                    P0[i] = std::max(0.f, ((float)row[x][0] - blackGlobal) / denom);
                    P1[i] = std::max(0.f, ((float)row[x][1] - blackGlobal) / denom);
                    P2[i] = std::max(0.f, ((float)row[x][2] - blackGlobal) / denom);
                }
            }
            PostProgress(jobID, @"libraw", @"demosaic");
            unsigned xp[6][6];
            for (int r=0;r<6;++r) for (int c=0;c<6;++c)
                xp[r][c] = (unsigned)(unsigned char)raw->idata.xtrans[r][c];

            demosaicOK = (bridge_xtrans_demosaic(P0.get(), P1.get(), P2.get(), W, H, xp,
                                                 R.get(), G.get(), B.get()) == 0);
        }
        PostProgress(jobID, @"libraw", @"convert_rgb");

        // ---- PP3 linear ops already applied above ----
        const int   iters = P.deconvIter;
        const float amt   = P.deconvAmount;
        const float rad   = fmaxf(0.05f, P.deconvRadius);
        if (!demosaicOK) {
            // --- Load largest embedded preview ---
            NSURL *u = [NSURL fileURLWithPath:rawPath];
            CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)u,
                              (__bridge CFDictionaryRef)@{(id)kCGImageSourceShouldCache:@NO});
            if (!src) { libraw_close(raw); PostProgress(jobID, @"libraw", @"finish"); return nil; }

            size_t count = CGImageSourceGetCount(src);
            int bestIndex = -1; long bestArea = -1;
            for (size_t i=0;i<count;++i) {
                CFDictionaryRef props = CGImageSourceCopyPropertiesAtIndex(src, i, NULL);
                if (!props) continue;
                int w=0,h=0;
                CFNumberRef wN=(CFNumberRef)CFDictionaryGetValue(props, kCGImagePropertyPixelWidth);
                CFNumberRef hN=(CFNumberRef)CFDictionaryGetValue(props, kCGImagePropertyPixelHeight);
                if (wN && hN) { CFNumberGetValue(wN,kCFNumberIntType,&w); CFNumberGetValue(hN,kCFNumberIntType,&h); }
                CFRelease(props);
                long area=(long)w*(long)h;
                if (w>0 && h>0 && area>bestArea) { bestArea=area; bestIndex=(int)i; }
            }

            int exif = 1;
            if (bestIndex >= 0) {
                CFDictionaryRef props = CGImageSourceCopyPropertiesAtIndex(src, bestIndex, NULL);
                if (props) { CFNumberRef n=(CFNumberRef)CFDictionaryGetValue(props, kCGImagePropertyOrientation);
                    if (n) CFNumberGetValue(n, kCFNumberIntType, &exif);
                    CFRelease(props);
                }
            }

            CGImageRef cg = (bestIndex>=0) ? CGImageSourceCreateImageAtIndex(src, bestIndex, NULL) : NULL;
            CFRelease(src);

            if (!cg) { libraw_close(raw); PostProgress(jobID, @"libraw", @"finish"); return nil; }

            // ---- Pull into BGRA, apply PP3, then optional Lab ops ----
            const int Wp = (int)CGImageGetWidth(cg), Hp = (int)CGImageGetHeight(cg);
            CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
            CGBitmapInfo bi = kCGBitmapByteOrder32Little | (CGBitmapInfo)kCGImageAlphaPremultipliedFirst;
            std::unique_ptr<uint8_t[]> BGRA(new uint8_t[Wp*Hp*4]);
            CGContextRef ctx = CGBitmapContextCreate(BGRA.get(), Wp, Hp, 8, Wp*4, cs, bi);
            if (ctx) {
                CGContextDrawImage(ctx, CGRectMake(0,0,Wp,Hp), cg);
                CGContextRelease(ctx);
            }
            if (cs) CGColorSpaceRelease(cs);
            CGImageRelease(cg);

            // 1) Tone ops (linear) from PP3
            RU_ApplyToneOps_OnBGRA(BGRA.get(), Wp, Hp, P);
            if (RU_ShouldSharpen(P)) {
                RU_ApplyPreviewSharpen_OnBGRA(BGRA.get(), Wp, Hp,
                                              P.deconvIter, P.deconvRadius, P.deconvAmount, P.deconvDamping);
            }

            // 2) Lab ops (preview)
            RU_ApplyLabOps_OnBGRA(BGRA.get(), Wp, Hp,    // <-- use Wp/Hp, not W/H
                                  P.chromaEnabled, P.chromaticity,
                                  P.cChromaEnabled, P.cChroma,
                                  P.jContrastEnabled, P.jContrast);
            
            // 3) Pack back to CGImage
            cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
            ctx = CGBitmapContextCreate(BGRA.get(), Wp, Hp, 8, Wp*4, cs, bi);
            CGImageRef cgOut = ctx ? CGBitmapContextCreateImage(ctx) : NULL;
            if (ctx) CGContextRelease(ctx);
            if (cs) CGColorSpaceRelease(cs);

            UIImage *ui = cgOut ? [UIImage imageWithCGImage:cgOut scale:1.0 orientation:UIImageOrientationUp] : nil;
            
            if (cgOut) CGImageRelease(cgOut);

            // Bake orientation once, from the RAW file EXIF
            int exifFromFile = RUExifOrientationFromFileC(rawPath.UTF8String);
            if (ui && exifFromFile != 1) {
                ui = RUApplyFinalOrientation(ui, RUFixPortraitEXIFIfBaked(ui.CGImage, exifFromFile));
            }

            libraw_close(raw);
            PostProgress(jobID, @"libraw", @"finish");
            return ui;
        }
 
        
        // After WB normalize to G=1...
        // --- compute neutral-Y normalization (preview EV bias) ---
        // Stash WB and cam->sRGB for later, while 'raw' is still alive.
        float M[9];
        buildCamToSRGB(raw->color, M);

        const float camR = raw->color.cam_mul[0] > 0 ? raw->color.cam_mul[0] : 1.f;
        const float camG = raw->color.cam_mul[1] > 0 ? raw->color.cam_mul[1] : 1.f;
        const float camB = raw->color.cam_mul[2] > 0 ? raw->color.cam_mul[2] : 1.f;

        const float rWB = camG / camR;
        const float bWB = camG / camB;
        PostProgress(jobID, @"libraw", @"convert_rgb");

        
        // We are still in LINEAR camera space here.
        // Apply WB to match full-res:
        for (size_t i=0; i<N; ++i) {
            R[i] *= rWB;                   // G stays as reference
            /* G[i] *= 1.f; */
            B[i] *= bWB;
        }

        // Convert camera -> linear sRGB using the SAME matrix as full-res:
        for (size_t i=0; i<N; ++i) {
            float ro, go, bo;
            mul3x3(M, R[i], G[i], B[i], ro, go, bo);
            R[i] = ro < 0.f ? 0.f : ro;
            G[i] = go < 0.f ? 0.f : go;
            B[i] = bo < 0.f ? 0.f : bo;
        }
        // If RLD is enabled, post start → per-iter → done
        // ...after mul3x3(M,...) loop (now in linear sRGB)

        if (iters > 0 && amt > 0.f && rad > 0.05f) {
            PostProgress(jobID, @"rld", @"iter", 0, iters);
            RU_RLD_Luma_Linear_WithProgress(R.get(), G.get(), B.get(),
                                            W, H, iters, rad, amt, P.deconvDamping,
                                            ^(int iter, int total) {
                PostProgress(jobID, @"rld", @"iter", iter, total);
            });
            PostProgress(jobID, @"rld", @"iter", iters, iters);
        } else {
            PostProgress(jobID, @"rld", @"skip", 0, 0);
        }
        // Always anchor the baseline with autoEV; slider adds on top.
        // Remove autoEV. Only apply user-set EV (from PP3 or slider):
        const float userEV = P.hasExposure ? P.exposureEV : 0.f;
        RU_ApplyExposureEV(R.get(), G.get(), B.get(), N, userEV);
        if (P.hasBlack)    RU_ApplyBlack(R.get(), G.get(), B.get(), N, P.black);
        if (P.hasShadows)  RU_ApplyShadows(R.get(), G.get(), B.get(), N, P.shadows);

        // NOTE: remove RU_NormalizeLumaPercentile calls here.
        // after it finishes:
        
        PostProgress(jobID, @"rld", @"iter", P.deconvIter, P.deconvIter);
        // Pack to 8-bit BGRA
        std::unique_ptr<uint8_t[]> BGRA(new uint8_t[N*4]);
        for (int i=0;i<N;++i){
            const uint8_t r = (uint8_t)lrintf(std::clamp(linear_to_srgb(std::clamp(R[i],0.f,1.f)),0.f,1.f)*255.f);
            const uint8_t g = (uint8_t)lrintf(std::clamp(linear_to_srgb(std::clamp(G[i],0.f,1.f)),0.f,1.f)*255.f);
            const uint8_t b = (uint8_t)lrintf(std::clamp(linear_to_srgb(std::clamp(B[i],0.f,1.f)),0.f,1.f)*255.f);
            BGRA[i*4+0] = b; BGRA[i*4+1] = g; BGRA[i*4+2] = r; BGRA[i*4+3] = 255;
        }

        // Optional Lab ops on preview buffer (to mimic your older path)
        RU_ApplyLabOps_OnBGRA(BGRA.get(), W, H,
                              P.chromaEnabled, P.chromaticity,
                              P.cChromaEnabled, P.cChroma,
                              P.jContrastEnabled, P.jContrast);

        CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        CGBitmapInfo bi = kCGBitmapByteOrder32Little | (CGBitmapInfo)kCGImageAlphaPremultipliedFirst;
        CGContextRef ctx = CGBitmapContextCreate(BGRA.get(), W, H, 8, W*4, cs, bi);
        CGImageRef cg = ctx ? CGBitmapContextCreateImage(ctx) : NULL;
        if (ctx) CGContextRelease(ctx);
        if (cs) CGColorSpaceRelease(cs);

        UIImage *ui = cg ? [UIImage imageWithCGImage:cg scale:1.0 orientation:UIImageOrientationUp] : nil;
        if (cg) CGImageRelease(cg);
        const int exifFromFile = RUExifOrientationFromFileC(rawPath.UTF8String);
        if (ui && exifFromFile != 1) {
            ui = RUApplyFinalOrientation(ui, RUFixPortraitEXIFIfBaked(ui.CGImage, exifFromFile));
        }
        return ui;    }
}

+ (nullable UIImage *)halfSizeSuperpixelAtPath:(NSString *)rawPath
                                       pp3Path:(NSString *)pp3Path
                                         jobID:(nullable NSString *)jobID
{
    if (!rawPath || rawPath.length == 0) return nil;
    if (![[NSFileManager defaultManager] fileExistsAtPath:rawPath]) return nil;
    
    // Load PP3
    RU_PP3 P; RU_LoadPP3(pp3Path.length ? pp3Path.UTF8String : NULL, P);
    
    PostProgress(jobID, @"libraw", @"open");
    libraw_data_t *raw = libraw_init(0);
    if (!raw) return nil;
    if (libraw_open_file(raw, rawPath.UTF8String)) { libraw_close(raw); return nil; }
    raw->params.half_size      = 1;     // superpixel
    raw->params.gamm[0]        = 1.0f;  // linear TRC
    raw->params.gamm[1]        = 1.0f;
    raw->params.no_auto_bright = 1;
    raw->params.use_camera_wb  = 1;     // <-- let LibRaw apply camera WB
    raw->params.output_color   = 1;     // <-- sRGB primaries
    raw->params.output_bps     = 16;
    raw->params.user_flip      = 0;    //
    if (libraw_unpack(raw))          { libraw_close(raw); return nil; }
    if (libraw_dcraw_process(raw))   { libraw_close(raw); return nil; }
    
      int merr = 0;
    libraw_processed_image_t *pi = libraw_dcraw_make_mem_image(raw, &merr);
    
    // 1) Build cam->sRGB matrix (same as full-res)
    float M[9];
    buildCamToSRGB(raw->color, M);
    
    // 2) White balance factors (normalize to G=1 like full-res)
    const float camR = raw->color.cam_mul[0] > 0 ? raw->color.cam_mul[0] : 1.f;
    const float camG = raw->color.cam_mul[1] > 0 ? raw->color.cam_mul[1] : 1.f;
    const float camB = raw->color.cam_mul[2] > 0 ? raw->color.cam_mul[2] : 1.f;
    
    if (!pi || merr != LIBRAW_SUCCESS) { if (pi) libraw_dcraw_clear_mem(pi); libraw_close(raw); return nil; }
    
    // ---- snapshot and validate ONCE ----
    const int     type   = (int)pi->type;
    const int     bits   = (int)pi->bits;           // 8 or 16
    const int     colors = (int)pi->colors;         // 3 or 4
    const int     W      = (int)pi->width;
    const int     H      = (int)pi->height;
    const size_t  N      = (size_t)W * (size_t)H;
    const size_t  dataSz = (size_t)pi->data_size;
    const void   *data   = pi->data;
    
    if (type != LIBRAW_IMAGE_BITMAP || !data || W<=0 || H<=0 || (bits!=8 && bits!=16) || colors < 3) {
        libraw_dcraw_clear_mem(pi); libraw_close(raw); return nil;
    }
    const size_t Bpc  = (size_t)bits/8;                         // 1 or 2
    const size_t need = N * (size_t)colors * Bpc;               // interleaved
    if (dataSz < need) {                                        // prevent OOB
        libraw_dcraw_clear_mem(pi); libraw_close(raw); return nil;
    }
    
    // ---- copy out to our own buffers exactly once ----
    std::unique_ptr<float[]> R(new float[N]), G(new float[N]), B(new float[N]);
    if (bits == 8) {
        const uint8_t *s = (const uint8_t*)data;
        for (size_t i=0;i<N;++i) {
            const size_t idx = i * (size_t)colors;
            R[i] = s[idx+0] / 255.f;
            G[i] = s[idx+1] / 255.f;
            B[i] = s[idx+2] / 255.f;
        }
    } else { // 16
        const uint16_t *s = (const uint16_t*)data;
        for (size_t i=0;i<N;++i) {
            const size_t idx = i * (size_t)colors;
            R[i] = s[idx+0] / 65535.f;
            G[i] = s[idx+1] / 65535.f;
            B[i] = s[idx+2] / 65535.f;
        }
    }
    
    // safe to free libraw buffers now
    libraw_dcraw_clear_mem(pi); pi = nullptr;
    libraw_close(raw);
    if (P.deconvIter > 0 && P.deconvAmount > 0.f && P.deconvRadius > 0.f) {
        PostProgress(jobID, @"rld", @"iter", 0, P.deconvIter); // show “RLD 0/N”
        RU_RLD_Luma_Linear_WithProgress(R.get(), G.get(), B.get(),
                                        W, H,
                                        P.deconvIter,
                                        fmaxf(0.05f, P.deconvRadius),
                                        P.deconvAmount,
                                        P.deconvDamping,
                                        ^(int iter, int total){
            dispatch_async(dispatch_get_main_queue(), ^{
                PostProgress(jobID, @"rld", @"iter", iter, total); // Swift shows “RLD iter/total”
            });
        });
        
    }
    // ---- linear tone ops ----
    if (P.hasExposure) RU_ApplyExposureEV(R.get(), G.get(), B.get(), (int)N, P.exposureEV);
    if (P.hasBlack)    RU_ApplyBlack    (R.get(), G.get(), B.get(), (int)N, P.black);
    if (P.hasShadows)  RU_ApplyShadows  (R.get(), G.get(), B.get(), (int)N, P.shadows);
    // 🔆 Preview brightness normalizer (only if user didn't set EV)
    // Sticky auto-EV normalization: always used as base, then slider is added
    NSString *evKey = RU_EVKey(rawPath, jobID);
    float baseEV = 0.f;

    
    const float previewNormEV = RU_AutoEVFromPercentile(R.get(), G.get(), B.get(), (int)N, 0.99f, 0.95f);
    const float userEV = P.hasExposure ? P.exposureEV : 0.f;
    RU_ApplyExposureEV(R.get(), G.get(), B.get(), (int)N, previewNormEV + userEV);
    
    // ---- pack to BGRA (sRGB gamma) ----
    // ---- Pack to BGRA sRGB ----
    std::unique_ptr<uint8_t[]> BGRA(new uint8_t[N*4]);
    for (size_t i=0;i<N;i++) {
        auto e = [](float x)->uint8_t {
            x = fmaxf(0.f, fminf(1.f, x));
            float y = (x<=0.0031308f)? 12.92f*x : 1.055f*powf(x,1.f/2.4f)-0.055f;
            return (uint8_t)lrintf(fmaxf(0.f, fminf(1.f, y))*255.f);
        };
        BGRA[i*4+2] = e(R[i]);
        BGRA[i*4+1] = e(G[i]);
        BGRA[i*4+0] = e(B[i]);
        BGRA[i*4+3] = 255;
    }
    
    // ✅ Apply Color Appearance/Lab adjustments in preview too
    if (P.chromaEnabled || P.cChromaEnabled || P.jContrastEnabled) {
        RU_ApplyLabOps_OnBGRA(BGRA.get(), W, H,
                              P.chromaEnabled,  P.chromaticity,
                              P.cChromaEnabled, P.cChroma,
                              P.jContrastEnabled, P.jContrast);
    }
    // ---- make UIImage (orientation Up; we’ll decide EXIF elsewhere) ----
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGBitmapInfo bi = kCGBitmapByteOrder32Little | (CGBitmapInfo)kCGImageAlphaPremultipliedFirst;
    CGContextRef ctx = CGBitmapContextCreate(BGRA.get(), W, H, 8, W*4, cs, bi);
    CGImageRef cg = ctx ? CGBitmapContextCreateImage(ctx) : NULL;
    if (ctx) CGContextRelease(ctx);
    if (cs) CGColorSpaceRelease(cs);
    UIImage *ui = cg ? [UIImage imageWithCGImage:cg scale:1.0 orientation:UIImageOrientationUp] : nil;
    
    // Apply RAW file EXIF once
    if (ui) {
        const int exifFromFile = RUExifOrientationFromFileC(rawPath.UTF8String);
        if (exifFromFile != 1) {
            ui = RUApplyFinalOrientation(ui, RUFixPortraitEXIFIfBaked(ui.CGImage, exifFromFile));
        }
    }
    return ui;
}


+ (nullable CGImageRef)createCGImage16FromRAWAtPath:(nonnull NSString *)rawPath jobID:(nullable NSString *)jobID __attribute__((cf_returns_retained)) __attribute__((swift_name("createCGImage16FromRAW(atPath:jobID:)"))) {
    return NULL;
}

+ (nullable UIImage *)fullResAMAZEAtPath:(nonnull NSString *)rawPath jobID:(nullable NSString *)jobID __attribute__((swift_name("fullResAMAZE(atPath:jobID:)"))) { return NULL;}

+ (nullable UIImage *)previewSuperpixelAtPath:(nonnull NSString *)rawPath jobID:(nullable NSString *)jobID __attribute__((swift_name("previewSuperpixel(atPath:jobID:)"))) { return NULL;
}

+ (CGSize)rawActiveSizeAtPath:(NSString *)rawPath {
    if (!rawPath) {
        return CGSizeZero;
    }

    const char *cpath = [rawPath fileSystemRepresentation];
    LibRaw raw;
    if (raw.open_file(cpath) != LIBRAW_SUCCESS ||
        raw.unpack() != LIBRAW_SUCCESS) {
        return CGSizeZero;
    }

    // Active area from LibRaw
    int w = raw.imgdata.sizes.raw_width;
    int h = raw.imgdata.sizes.raw_height;

    raw.recycle();

    return CGSizeMake(w, h);
}
@end


static UIImage *RUEmbeddedPreviewUIImageAtPathApplyingPP3(NSString *path, const RU_PP3 &P)
{
    NSURL *u = [NSURL fileURLWithPath:path];
    CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)u,
                                                      (__bridge CFDictionaryRef)@{(id)kCGImageSourceShouldCache:@NO});
    if (!src) return nil;
    
    // Pick largest raster subimage
    size_t count = CGImageSourceGetCount(src);
    int bestIndex = -1; long bestArea = -1;
    for (size_t i=0;i<count;++i) {
        CFDictionaryRef props = CGImageSourceCopyPropertiesAtIndex(src, i, NULL);
        if (!props) continue;
        int w=0,h=0;
        CFNumberRef wN=(CFNumberRef)CFDictionaryGetValue(props, kCGImagePropertyPixelWidth);
        CFNumberRef hN=(CFNumberRef)CFDictionaryGetValue(props, kCGImagePropertyPixelHeight);
        if (wN && hN) { CFNumberGetValue(wN,kCFNumberIntType,&w); CFNumberGetValue(hN,kCFNumberIntType,&h); }
        CFRelease(props);
        long area=(long)w*(long)h;
        if (w>0 && h>0 && area>bestArea) { bestArea=area; bestIndex=(int)i; }
    }
    if (bestIndex < 0) { CFRelease(src); return nil; }
    
    // Decode CGImage (no auto transform)
    CGImageRef cg = CGImageSourceCreateImageAtIndex(src, bestIndex, NULL);
    CFRelease(src);
    if (!cg) return nil;
    
    const size_t W = CGImageGetWidth(cg), H = CGImageGetHeight(cg);
    if (W==0 || H==0) { CGImageRelease(cg); return nil; }
    
    // Draw into BGRA8 buffer
    std::unique_ptr<uint8_t[]> BGRA(new uint8_t[W*H*4]);
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGBitmapInfo bi = kCGBitmapByteOrder32Little |
    (CGBitmapInfo)kCGImageAlphaPremultipliedFirst;
    CGContextRef ctx = CGBitmapContextCreate(BGRA.get(), W, H, 8, W*4, cs, bi);
    if (!ctx) { if (cs) CGColorSpaceRelease(cs); CGImageRelease(cg); return nil; }
    CGContextDrawImage(ctx, CGRectMake(0,0,W,H), cg);
    
    // Apply tone ops (linear) then Lab ops (both in-place)
    RU_ApplyToneOps_OnBGRA(BGRA.get(), (int)W, (int)H, P);
    RU_ApplyLabOps_OnBGRA(BGRA.get(), (int)W, (int)H,
                          P.chromaEnabled, P.chromaticity,
                          P.cChromaEnabled, P.cChroma,
                          P.jContrastEnabled, P.jContrast);
    
    // Create CGImage back from the edited buffer
    CGImageRef outCG = CGBitmapContextCreateImage(ctx);
    
    CGContextRelease(ctx);
    if (cs) CGColorSpaceRelease(cs);
    CGImageRelease(cg);
    if (!outCG) return nil;
    
    // Apply EXIF from the RAW file (single source of truth for orientation)
    UIImage *ui = nil;
    // --- Get EXIF orientation FROM THE PREVIEW SUBIMAGE (bestIndex) ---
    // --- Get EXIF orientation of the largest preview and apply once ---
    int exif = RUExifOrientationFromLargestPreviewC(path.UTF8String);
    exif = RUFixPortraitEXIFIfBaked(outCG, exif);
    
    // Apply that EXIF exactly once
    //    UIImage *ui = nil;
    if (exif != 1) {
        CGImageRef rot = RUCreateCGImageApplyingEXIF_KnownGood(outCG, exif);
        CGImageRelease(outCG);
        if (!rot) return nil;
        ui = [UIImage imageWithCGImage:rot scale:1.0 orientation:UIImageOrientationUp];
        CGImageRelease(rot);
    } else {
        ui = [UIImage imageWithCGImage:outCG scale:1.0 orientation:UIImageOrientationUp];
        CGImageRelease(outCG);
    }
    return ui;
}
    
    // Implementation
    static void RU_ApplyPreviewSharpen_OnBGRA(uint8_t *bgra, int W, int H,
                                              int iters, float radius, float amount, float dampPct)
    {
        if (iters <= 0 || amount <= 0.f || radius <= 0.f) return;
        const int N = W*H;
        std::unique_ptr<float[]> R(new float[N]), G(new float[N]), B(new float[N]);
        
        // sRGB8 -> linear float
        for (int i=0;i<N;++i){
            float r = bgra[i*4+2] / 255.f;
            float g = bgra[i*4+1] / 255.f;
            float b = bgra[i*4+0] / 255.f;
            R[i] = ru_srgb_to_linear(r);
            G[i] = ru_srgb_to_linear(g);
            B[i] = ru_srgb_to_linear(b);
        }
        
        RU_ApplyPreviewSharpen(R.get(), G.get(), B.get(), W, H, iters, radius, amount, dampPct);
        
        // linear -> sRGB8
        for (int i=0;i<N;++i){
            float r = std::clamp(ru_linear_to_srgb(std::clamp(R[i],0.f,1.f)), 0.f, 1.f);
            float g = std::clamp(ru_linear_to_srgb(std::clamp(G[i],0.f,1.f)), 0.f, 1.f);
            float b = std::clamp(ru_linear_to_srgb(std::clamp(B[i],0.f,1.f)), 0.f, 1.f);
            bgra[i*4+2] = (uint8_t)lrintf(r*255.f);
            bgra[i*4+1] = (uint8_t)lrintf(g*255.f);
            bgra[i*4+0] = (uint8_t)lrintf(b*255.f);
        }
    }

// ======= RL-Deconvolution (luminance, linear) =======
static inline float ru_clamp01(float x){ return x<0.f?0.f:(x>1.f?1.f:x); }

// Simple separable Gaussian using 3 box blurs (fast good-enough)
static void ru_box_blur_1D(float* dst, const float* src, int n, int r) {
    if (r <= 0) { memcpy(dst, src, n*sizeof(float)); return; }
    float invWin = 1.f / (2*r+1);
    float acc = 0.f;
    int i=0;
    for (int k=-r; k<=r; ++k) acc += src[(k<0?0:(k>=n?n-1:k))];
    for (i=0; i<n; ++i) {
        dst[i] = acc * invWin;
        int i_add = i+r+1; if (i_add>=n) i_add = n-1;
        int i_sub = i-r;   if (i_sub<0)  i_sub = 0;
        acc += src[i_add] - src[i_sub];
    }
}

static void ru_gauss_blur(float* buf, float* tmp, int W, int H, float radius) {
    if (radius <= 0.05f) return;
    // approximate gaussian with 3 box-blurs, radius->boxR
    int r = (int)lrintf(fmaxf(1.f, radius));
    // horizontal then vertical, 3 passes
    // pass 1
    for (int y=0; y<H; ++y) ru_box_blur_1D(tmp + y*W, buf + y*W, W, r);
    for (int x=0; x<W; ++x) {
        // vertical on tmp -> buf
        // use a small stack buffer pointer math
        float acc = 0.f; float invWin = 1.f/(2*r+1);
  
        for (int k=-r; k<=r; ++k) {
            int yy = k<0?0:(k>=H?H-1:k);
            acc += tmp[yy*W + x];
        }
        for (int y=0; y<H; ++y) {
            buf[y*W + x] = acc * invWin;
            int y_add = y+r+1; if (y_add>=H) y_add = H-1;
            int y_sub = y-r;   if (y_sub<0)  y_sub = 0;
            acc += tmp[y_add*W + x] - tmp[y_sub*W + x];
        }
    }
    // pass 2
    for (int y=0; y<H; ++y) ru_box_blur_1D(tmp + y*W, buf + y*W, W, r);
    for (int x=0; x<W; ++x) {
        float acc = 0.f; float invWin = 1.f/(2*r+1);
        for (int k=-r; k<=r; ++k) {
            int yy = k<0?0:(k>=H?H-1:k);
            acc += tmp[yy*W + x];
        }
        for (int y=0; y<H; ++y) {
            buf[y*W + x] = acc * invWin;
            int y_add = y+r+1; if (y_add>=H) y_add = H-1;
            int y_sub = y-r;   if (y_sub<0)  y_sub = 0;
            acc += tmp[y_add*W + x] - tmp[y_sub*W + x];
        }
    }
    // pass 3
    for (int y=0; y<H; ++y) ru_box_blur_1D(tmp + y*W, buf + y*W, W, r);
    for (int x=0; x<W; ++x) {
        float acc = 0.f; float invWin = 1.f/(2*r+1);
        for (int k=-r; k<=r; ++k) {
            int yy = k<0?0:(k>=H?H-1:k);
            acc += tmp[yy*W + x];
        }
        for (int y=0; y<H; ++y) {
            buf[y*W + x] = acc * invWin;
            int y_add = y+r+1; if (y_add>=H) y_add = H-1;
            int y_sub = y-r;   if (y_sub<0)  y_sub = 0;
            acc += tmp[y_add*W + x] - tmp[y_sub*W + x];
        }
    }
}
static void RU_RLD_Luma_Linear_WithProgress(float *R, float *G, float *B,
                                            int W, int H,
                                            int iterations, float radius,
                                            float amountPct, float dampingPct,
                                            RU_RLDProgressBlock progress)
{
    if (iterations <= 0 || amountPct <= 0.f || radius <= 0.05f) return;

    const int N = W*H;
    std::unique_ptr<float[]> Y  (new float[N]);
    std::unique_ptr<float[]> E  (new float[N]);
    std::unique_ptr<float[]> tmp(new float[N]);
    std::unique_ptr<float[]> buf(new float[N]);

    // build initial luminance (linear)
    for (int i=0;i<N;++i) {
        float y = 0.2126f*R[i] + 0.7152f*G[i] + 0.0722f*B[i];
        Y[i] = std::clamp(y, 0.f, 1.f);
        E[i] = Y[i];
    }

    const float eps  = 1e-6f;
    const float damp = std::clamp(dampingPct/100.f, 0.f, 0.99f);
    const float rMin = 1.f - damp, rMax = 1.f + damp;
    const float kAmt = std::min(2.f, amountPct/100.f); // 0..2

    for (int t=0; t<iterations; ++t) {
        // blurred = PSF * E
        memcpy(buf.get(), E.get(), N*sizeof(float));
        ru_gauss_blur(buf.get(), tmp.get(), W, H, radius);

        // ratio = Y / blurred (damped)
        for (int i=0;i<N;++i) {
            float ratio = Y[i] / (buf[i] + eps);
            if (damp>0.f) ratio = std::clamp(ratio, rMin, rMax);
            tmp[i] = ratio;
        }

        // correction = PSF^T * ratio (PSF symmetric)
        memcpy(buf.get(), tmp.get(), N*sizeof(float));
        ru_gauss_blur(buf.get(), tmp.get(), W, H, radius);

        // E *= correction
        for (int i=0;i<N;++i) E[i] = std::clamp(E[i] * tmp[i], 0.f, 1.f);

        // Progress tick only (no rendering)
        if (progress) progress(t+1, iterations);
        
    }

    // reinject sharpened luma via gain = E/Y (blend by amount)
    for (int i=0;i<N;++i) {
        float gain = E[i] / (Y[i] + eps);
        gain = 1.f + (gain - 1.f) * kAmt;
        R[i] = std::clamp(R[i]*gain, 0.f, 1.f);
        G[i] = std::clamp(G[i]*gain, 0.f, 1.f);
        B[i] = std::clamp(B[i]*gain, 0.f, 1.f);
    }
}

// Compute the EV that would map the p-th luminance percentile to `target`.
// Does NOT modify R/G/B; returns EV (can be negative/positive).

