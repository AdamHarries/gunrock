// ----------------------------------------------------------------------------
// Gunrock -- Fast and Efficient GPU Graph Library
// ----------------------------------------------------------------------------
// This source code is distributed under the terms of LICENSE.TXT
// in the root directory of this source distribution.
// ----------------------------------------------------------------------------

/**
 * @file topk_app.cu
 *
 * @brief top k degree centralities application
 */

#include <gunrock/gunrock.h>
#include <gunrock/graphio/market.cuh>
#include <gunrock/app/topk/topk_enactor.cuh>
#include <gunrock/app/topk/topk_problem.cuh>

using namespace gunrock;
using namespace gunrock::util;
using namespace gunrock::oprtr;
using namespace gunrock::app::topk;

/*
 * @brief searches for a value in sorted array
 *
 * @tparam VertexId
 * @tparam SizeT
 *
 * @param[in] arr is an array to search in
 * @param[in] val is searched value
 * @param[in] left  is an index of left  boundary
 * @param[in] right is an index of right boundary
 *
 * return the searched value, if it presents in the array
 * return -1 if the searched value is absent
 */
template <typename VertexId, typename SizeT>
int binary_search(VertexId *arr, VertexId val, SizeT left, SizeT right) {
  while (left <= right) {
    int mid = left + (right - left) / 2;
    if (arr[mid] == val) {
      return arr[mid];
    } else if (arr[mid] > val) {
      right = mid - 1;
    } else {
      left = mid + 1;
    }
  }
  return -1;
}

/**
 * @brief Build Sub-Graph Contains Only Top K Nodes
 *
 * @tparam VertexId
 * @tparam SizeT
 *
 * @param[out] subgraph output subgraph of topk problem
 * @param[in]  graph_original input graph need to process on
 * @param[in]  graph_reversed reversed input graph need to process on
 * @param[out] node_ids output top-k node_ids
 * @param[in] top_nodes Number of nodes needed to process on
 */
template <typename VertexId, typename Value, typename SizeT>
void build_topk_subgraph(GRGraph *subgraph,
                         const Csr<VertexId, Value, SizeT> &graph_original,
                         const Csr<VertexId, Value, SizeT> &graph_reversed,
                         VertexId *node_ids, int top_nodes) {
  int search_return = 0;
  int search_count = 0;
  std::vector<VertexId> node_ids_vec(node_ids, node_ids + top_nodes);
  std::vector<int> sub_row_offsets;
  std::vector<VertexId> sub_col_indices;

  // build row_offsets and col_indices of sub-graph
  sub_row_offsets.push_back(0);  // start of row_offsets
  for (int i = 0; i < top_nodes; ++i) {
    for (int j = 0; j < top_nodes; ++j) {
      /*
      // debug print
      printf("searching %d in column_indices[%d, %d) = [", node_ids[j],
      graph_original.row_offsets[node_ids[i]],
      graph_original.row_offsets[node_ids[i]+1]);
      for (int k = graph_original.row_offsets[node_ids[i]];
      k < graph_original.row_offsets[node_ids[i]+1]; ++k)
      {
      printf(" %d", graph_original.column_indices[k]);
      }
      printf("]\n");
      */
      search_return = binary_search<VertexId, SizeT>(
          graph_original.column_indices, node_ids[j],
          graph_original.row_offsets[node_ids[i]],       // [left
          graph_original.row_offsets[node_ids[i] + 1]);  // right)
      // filter col_indices
      if (search_return != -1) {
        ++search_count;
        // TODO: improve efficiency
        search_return =
            std::find(node_ids_vec.begin(), node_ids_vec.end(), search_return) -
            node_ids_vec.begin();
        sub_col_indices.push_back(search_return);
      }
    }
    // build sub_row_offsets
    search_count += sub_row_offsets[sub_row_offsets.size() - 1];
    sub_row_offsets.push_back(search_count);
    search_count = 0;
  }

  // generate subgraph of top k nodes
  subgraph->num_nodes = top_nodes;
  subgraph->num_edges = sub_col_indices.size();
  subgraph->row_offsets = &sub_row_offsets[0];
  subgraph->col_indices = &sub_col_indices[0];

  /*
  // display sub-graph
  Csr<int, int, int> test_graph(false);
  test_graph.nodes = subgraph->num_nodes;
  test_graph.edges = subgraph->num_edges;
  test_graph.row_offsets    = (int*)subgraph->row_offsets;
  test_graph.column_indices = (int*)subgraph->col_indices;

  test_graph.DisplayGraph();

  test_graph.row_offsets    = NULL;
  test_graph.column_indices = NULL;
  */

  // clean up
  node_ids_vec.clear();
  sub_row_offsets.clear();
  sub_col_indices.clear();
}

/**
 * @brief Run TopK
 *
 * @tparam VertexId
 * @tparam Value
 * @tparam SizeT
 *
 * @param[out] graph_out output subgraph of topk problem
 * @param[out] node_ids return the top k nodes
 * @param[out] in_degrees  return associated centrality
 * @param[out] out_degrees return associated centrality
 * @param[in]  graph_original graph to the CSR graph we process on
 * @param[in]  graph_reversed graph to the CSR graph we process on
 * @param[in]  top_nodes k value for topk problem
 *
 */
template <typename VertexId, typename Value, typename SizeT>
void run_topk(GRGraph *graph_out, VertexId *node_ids, Value *in_degrees,
              Value *out_degrees,
              const Csr<VertexId, Value, SizeT> &graph_original,
              const Csr<VertexId, Value, SizeT> &graph_reversed,
              SizeT top_nodes) {
  typedef TOPKProblem<VertexId, SizeT, Value> Problem;
  TOPKEnactor<false> enactor(false);
  Problem *problem = new Problem;
  top_nodes =
      (top_nodes > graph_original.nodes) ? graph_original.nodes : top_nodes;

  util::GRError(problem->Init(false, graph_original, graph_reversed, 1),
                "Problem TOPK Initialization Failed", __FILE__, __LINE__);

  util::GRError(problem->Reset(enactor.GetFrontierType()),
                "TOPK Problem Data Reset Failed", __FILE__, __LINE__);

  util::GRError(enactor.template Enact<Problem>(problem, top_nodes),
                "TOPK Problem Enact Failed", __FILE__, __LINE__);

  util::GRError(problem->Extract(node_ids, in_degrees, out_degrees, top_nodes),
                "TOPK Problem Data Extraction Failed", __FILE__, __LINE__);

  // build vertex-induced subgraph contains only top k nodes
  build_topk_subgraph<VertexId, Value, SizeT>(
      graph_out, graph_original, graph_reversed, (int *)node_ids, top_nodes);

  if (problem) {
    delete problem;
  }
  cudaDeviceSynchronize();
}

/**
 * @brief dispatch function to handle data_types
 *
 * @param[out] graph_o     GRGraph type output
 * @param[out] node_ids    output top k node ids
 * @param[out] in_degrees  output top k in-degree centralities
 * @param[out] out_degrees output top k out-degree centralities
 * @param[in]  graph_i     GRGraph type input graph
 * @param[in]  config      topk specific configurations
 * @param[in]  data_t      topk data_t configurations
 */
void dispatch_topk(GRGraph *graph_o, void *node_ids, void *in_degrees,
                   void *out_degrees, const GRGraph *graph_i,
                   const GRSetup config, const GRTypes data_t) {
  switch (data_t.VTXID_TYPE) {
    case VTXID_INT: {
      switch (data_t.SIZET_TYPE) {
        case SIZET_INT: {
          switch (data_t.VALUE_TYPE) {
            case VALUE_INT: {  // template type = <int, int, int>
              Csr<int, int, int> graph_original(false);
              graph_original.nodes = graph_i->num_nodes;
              graph_original.edges = graph_i->num_edges;
              graph_original.row_offsets = (int *)graph_i->row_offsets;
              graph_original.column_indices = (int *)graph_i->col_indices;
              Csr<int, int, int> graph_reversed(false);
              graph_reversed.nodes = graph_i->num_nodes;
              graph_reversed.edges = graph_i->num_edges;
              graph_reversed.row_offsets = (int *)graph_i->col_offsets;
              graph_reversed.column_indices = (int *)graph_i->row_indices;

              run_topk<int, int, int>(graph_o, (int *)node_ids,
                                      (int *)in_degrees, (int *)out_degrees,
                                      graph_original, graph_reversed,
                                      config.top_nodes);

              // reset for free memory
              graph_original.row_offsets = NULL;
              graph_original.column_indices = NULL;
              graph_reversed.row_offsets = NULL;
              graph_reversed.column_indices = NULL;
              break;
            }
            case VALUE_UINT: {  // template type = <int, uint, int>
              printf("Not Yet Support This DataType Combination.\n");
              break;
            }
            case VALUE_FLOAT: {  // template type = <int, float, int>
              printf("Not Yet Support This DataType Combination.\n");
              break;
            }
          }
          break;
        }
      }
      break;
    }
  }
}

/*
 * @brief topk dispatch function base on gunrock data types
 *
 * @param[out] graph_o     output subgraph of topk problem
 * @param[out] node_ids    output top k node_ids
 * @param[out] in_degrees  output associated centrality values
 * @param[out] out_degrees output associated centrality values
 * @param[in]  graph_i     input graph need to process on
 * @param[in]  config      gunrock primitive specific configurations
 * @param[in]  data_t      gunrock data_t struct
 */
void gunrock_topk(GRGraph *graph_o, void *node_ids, void *in_degrees,
                  void *out_degrees, const GRGraph *graph_i,
                  const GRSetup config, const GRTypes data_t) {
  dispatch_topk(graph_o, node_ids, in_degrees, out_degrees, graph_i, config,
                data_t);
}

// Leave this at the end of the file
// Local Variables:
// mode:c++
// c-file-style: "NVIDIA"
// End:
