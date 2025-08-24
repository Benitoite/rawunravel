//
//  amaze_demosaic.h
//  RAWUnravel
//
//  Created by Richard Barber on 8/14/25.
//


#ifndef _AMAZE_DEMOSAIC_H_
#define _AMAZE_DEMOSAIC_H_

#ifdef __cplusplus
extern "C" {
#endif

/**
 * AMAZE demosaicing function.
 *
 * @param in      Pointer to single-channel Bayer input (float, normalized 0–1)
 * @param W       Image width
 * @param H       Image height
 * @param cfarray CFA pattern in 2×2 form (R=0, G=1, B=2)
 * @param outR    Pointer to float buffer for R output (size W×H)
 * @param outG    Pointer to float buffer for G output (size W×H)
 * @param outB    Pointer to float buffer for B output (size W×H)
 * @return 0 on success
 */
int bridge_amaze_demosaic(const float *in, int W, int H, const unsigned cfarray[4],
                   float *outR, float *outG, float *outB);

#ifdef __cplusplus
}
#endif

#endif // _AMAZE_DEMOSAIC_H_
