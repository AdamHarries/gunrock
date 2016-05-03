// ----------------------------------------------------------------------------
// Gunrock -- Fast and Efficient GPU Graph Library
// ----------------------------------------------------------------------------
// This source code is distributed under the terms of LICENSE.TXT
// in the root directory of this source distribution.

/**
 * @file
 * market.cuh
 *
 * @brief R-MAT Graph Construction Routines
 */

#pragma once

#include <math.h>
#include <stdio.h>

#include <gunrock/graphio/utils.cuh>

namespace gunrock {
namespace graphio {

inline double Sprng() { return double(rand()) / RAND_MAX; }

inline bool Flip() { return (rand() >= RAND_MAX / 2); }

template <typename VertexId>
void ChoosePartition(VertexId *u, VertexId *v, VertexId step, double a,
                     double b, double c, double d) {
  double p;
  p = Sprng();

  if (p < a) {
    // do nothing
  } else if ((a < p) && (p < a + b)) {
    *v = *v + step;
  } else if ((a + b < p) && (p < a + b + c)) {
    *u = *u + step;
  } else if ((a + b + c < p) && (p < a + b + c + d)) {
    *u = *u + step;
    *v = *v + step;
  }
}

void VaryParams(double *a, double *b, double *c, double *d) {
  double v, S;

  // Allow a max. of 5% variation
  v = 0.05;

  if (Flip()) {
    *a += *a *v *Sprng();
  } else {
    *a -= *a *v *Sprng();
  }
  if (Flip()) {
    *b += *b *v *Sprng();
  } else {
    *b -= *b *v *Sprng();
  }
  if (Flip()) {
    *c += *c *v *Sprng();
  } else {
    *c -= *c *v *Sprng();
  }
  if (Flip()) {
    *d += *d *v *Sprng();
  } else {
    *d -= *d *v *Sprng();
  }

  S = *a + *b + *c + *d;

  *a = *a / S;
  *b = *b / S;
  *c = *c / S;
  *d = *d / S;
}

/**
 * @brief Builds a R-MAT CSR graph
 */
template <bool WITH_VALUES, typename VertexId, typename Value, typename SizeT>
int BuildRmatGraph(SizeT nodes, SizeT edges, Csr<VertexId, Value, SizeT> &graph,
                   bool undirected, double a0 = 0.55, double b0 = 0.2,
                   double c0 = 0.2, double d0 = 0.05, bool quiet = false) {
  typedef Coo<VertexId, Value> EdgeTupleType;

  if ((nodes < 0) || (edges < 0)) {
    fprintf(stderr, "Invalid graph size: nodes=%d, edges=%d", nodes, edges);
    return -1;
  }

  // construct COO format graph

  VertexId directed_edges = (undirected) ? edges * 2 : edges;
  EdgeTupleType *coo =
      (EdgeTupleType *)malloc(sizeof(EdgeTupleType) * directed_edges);

  for (SizeT i = 0; i < edges; i++) {
    double a = a0;
    double b = b0;
    double c = c0;
    double d = d0;

    VertexId u = 1;
    VertexId v = 1;
    VertexId step = nodes / 2;

    while (step >= 1) {
      ChoosePartition(&u, &v, step, a, b, c, d);
      step /= 2;
      VaryParams(&a, &b, &c, &d);
    }

    // create edge
    coo[i].row = u - 1;  // zero-based
    coo[i].col = v - 1;  // zero-based
    coo[i].val = 1;

    if (undirected) {
      // reverse edge
      coo[edges + i].row = coo[i].col;
      coo[edges + i].col = coo[i].row;
      coo[edges + i].val = 1;
    }
  }

  // convert COO to CSR
  char *out_file = NULL;  // TODO: currently does not support write CSR file
  graph.template FromCoo<WITH_VALUES>(out_file, coo, nodes, directed_edges,
                                      quiet);

  free(coo);

  return 0;
}

}  // namespace graphio
}  // namespace gunrock

// Leave this at the end of the file
// Local Variables:
// mode:c++
// c-file-style: "NVIDIA"
// End:
