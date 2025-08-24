//
//  xtrans_demosaic.h
//  RAWUnravel
//
//  Created by Richard Barber on 8/14/25.
//


#ifndef _XTRANS_DEMOSAIC_H_
#define _XTRANS_DEMOSAIC_H_

#ifdef __cplusplus
extern "C" {
#endif

/**
 * X-Trans demosaicing function.
 *
 * @param P0      Pointer to float buffer for first plane
 * @param P1      Pointer to float buffer for second plane
 * @param P2      Pointer to float buffer for third plane
 * @param W       Image width
 * @param H       Image height
 * @param xtrans  6×6 CFA pattern (values: 0=R, 1=G, 2=B)
 * @param outR    Pointer to float buffer for R output (size W×H)
 * @param outG    Pointer to float buffer for G output (size W×H)
 * @param outB    Pointer to float buffer for B output (size W×H)
 * @return 0 on success
 */
int xtrans_demosaic(const float *P0, const float *P1, const float *P2,
                    int W, int H, const unsigned xtrans[6][6],
                    float *outR, float *outG, float *outB);

#ifdef __cplusplus
}
#endif

#endif // _XTRANS_DEMOSAIC_H_
