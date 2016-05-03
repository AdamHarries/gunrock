// ----------------------------------------------------------------------------
// Gunrock -- Fast and Efficient GPU Graph Library
// ----------------------------------------------------------------------------
// This source code is distributed under the terms of LICENSE.TXT
// in the root directory of this source distribution.
// ----------------------------------------------------------------------------
/**
 * @file
 * pr_functor.cuh
 *
 * @brief Device functions for PR problem.
 */

#pragma once

#include <gunrock/app/problem_base.cuh>
#include <gunrock/app/pr/pr_problem.cuh>

namespace gunrock {
namespace app {
namespace pr {

/**
 * @brief Structure contains device functions in PR graph traverse.
 *
 * @tparam VertexId    Type of signed integer to use as vertex id (e.g., uint32)
 * @tparam SizeT       Type of unsigned integer to use for array indexing.
 *(e.g., uint32)
 * @tparam ProblemData Problem data type which contains data slice for PR
 *problem
 *
 */
template <typename VertexId, typename SizeT, typename Value,
          typename ProblemData>
struct PRFunctor {
  typedef typename ProblemData::DataSlice DataSlice;

  /**
   * @brief Forward Edge Mapping condition function. Check if the
   * destination node has been claimed as someone else's child.
   *
   * @param[in] s_id Vertex Id of the edge source node
   * @param[in] d_id Vertex Id of the edge destination node
   * @param[in] problem Data slice object
   * @param[in] e_id output edge id
   * @param[in] e_id_in input edge id
   *
   * \return Whether to load the apply function for the edge and
   *         include the destination node in the next frontier.
   */
  static __device__ __forceinline__ bool CondEdge(VertexId s_id, VertexId d_id,
                                                  DataSlice *problem,
                                                  VertexId e_id = 0,
                                                  VertexId e_id_in = 0) {
    return true;
  }

  /**
   * @brief Forward Edge Mapping apply function. Now we know the source node
   * has succeeded in claiming child, so it is safe to set label to its child
   * node (destination node).
   *
   * @param[in] s_id Vertex Id of the edge source node
   * @param[in] d_id Vertex Id of the edge destination node
   * @param[in] problem Data slice object
   * @param[in] e_id output edge id
   * @param[in] e_id_in input edge id
   *
   */
  static __device__ __forceinline__ void ApplyEdge(VertexId s_id, VertexId d_id,
                                                   DataSlice *problem,
                                                   VertexId e_id = 0,
                                                   VertexId e_id_in = 0) {
    atomicAdd(&problem->d_rank_next[d_id],
              problem->d_rank_curr[s_id] / problem->d_degrees[s_id]);
  }

  /**
   * @brief Vertex mapping condition function. Check if the Vertex Id
   *        is valid (not equal to -1). Personal PageRank feature will
   *        be activated when a source node ID is set.
   *
   * @param[in] node Vertex Id
   * @param[in] problem Data slice object
   * @param[in] v auxiliary value
   *
   * \return Whether to load the apply function for the node and
   *         include it in the outgoing vertex frontier.
   */
  static __device__ __forceinline__ bool CondFilter(VertexId node,
                                                    DataSlice *problem,
                                                    Value v = 0,
                                                    SizeT nid = 0) {
    Value delta = problem->d_delta[0];
    problem->d_rank_next[node] =
        (1.0 - delta) + delta * problem->d_rank_next[node];
    Value diff = fabs(problem->d_rank_next[node] - problem->d_rank_curr[node]);
    return (diff >= (Value)problem->d_threshold[0]);
  }

  /**
   * @brief Vertex mapping apply function. Doing nothing for PR problem.
   *
   * @param[in] node Vertex Id
   * @param[in] problem Data slice object
   * @param[in] v auxiliary value
   *
   */
  static __device__ __forceinline__ void ApplyFilter(VertexId node,
                                                     DataSlice *problem,
                                                     Value v = 0,
                                                     SizeT nid = 0) {
    // Doing nothing here
  }
};

}  // pr
}  // app
}  // gunrock

// Leave this at the end of the file
// Local Variables:
// mode:c++
// c-file-style: "NVIDIA"
// End:
