// ----------------------------------------------------------------------------
// Gunrock -- Fast and Efficient GPU Graph Library
// ----------------------------------------------------------------------------
// This source code is distributed under the terms of LICENSE.TXT
// in the root directory of this source distribution.
// ----------------------------------------------------------------------------

/**
 * @file
 * utils.cuh
 *
 * @brief General graph-building utility routines
 */

#pragma once

#include <time.h>
#include <stdio.h>

#include <algorithm>

#include <gunrock/util/error_utils.cuh>
#include <gunrock/util/random_bits.h>

#include <gunrock/coo.cuh>
#include <gunrock/csr.cuh>

namespace gunrock {
namespace graphio {

/**
 * @brief Generates a random node-ID in the range of [0, num_nodes)
 *
 * @param[in] num_nodes Number of nodes in Graph
 *
 * \return random node-ID
 */
template <typename SizeT>
SizeT RandomNode(SizeT num_nodes) {
  SizeT node_id;
  util::RandomBits(node_id);
  if (node_id < 0) node_id *= -1;
  return node_id % num_nodes;
}

}  // namespace graphio
}  // namespace gunrock

// Leave this at the end of the file
// Local Variables:
// mode:c++
// c-file-style: "NVIDIA"
// End:
