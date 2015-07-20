// ----------------------------------------------------------------
// Gunrock -- Fast and Efficient GPU Graph Library
// ----------------------------------------------------------------
// This source code is distributed under the terms of LICENSE.TXT
// in the root directory of this source distribution.
// ----------------------------------------------------------------

/**
 * @file
 * salsa_enactor.cuh
 *
 * @brief SALSA (Stochastic Approach for Link-Structure Analysis) Problem Enactor
 */

#pragma once

#include <gunrock/util/kernel_runtime_stats.cuh>
#include <gunrock/util/test_utils.cuh>

#include <gunrock/oprtr/advance/kernel.cuh>
#include <gunrock/oprtr/advance/kernel_policy.cuh>
#include <gunrock/oprtr/filter/kernel.cuh>
#include <gunrock/oprtr/filter/kernel_policy.cuh>

#include <gunrock/app/enactor_base.cuh>
#include <gunrock/app/salsa/salsa_problem.cuh>
#include <gunrock/app/salsa/salsa_functor.cuh>

#include <moderngpu.cuh>

using namespace mgpu;

namespace gunrock {
namespace app {
namespace salsa {

/**
 * @brief SALSA problem enactor class.
 *
 * @tparam INSTRUMWENT Boolean type to show whether or not to collect per-CTA clock-count statistics
 */
template<bool INSTRUMENT>
class SALSAEnactor : public EnactorBase
{
    // Members
    protected:

    volatile int        *done;
    int                 *d_done;

    // Methods
    protected:

    /**
     * @brief Prepare the enactor for SALSA kernel call. Must be called prior to each SALSA search.
     *
     * @param[in] problem SALSA Problem object which holds the graph data and SALSA problem data to compute.
     * @param[in] edge_map_grid_size CTA occupancy for edge mapping kernel call.
     * @param[in] vertex_map_grid_size CTA occupancy for vertex mapping kernel call.
     *
     * \return cudaError_t object which indicates the success of all CUDA function calls.
     */
    template <typename ProblemData>
    cudaError_t Setup(
        ProblemData *problem)
    {
        typedef typename ProblemData::SizeT         SizeT;
        typedef typename ProblemData::VertexId      VertexId;
        
        cudaError_t retval = cudaSuccess;

        return retval;
    }

    public:

    /**
     * @brief SALSAEnactor constructor
     */
    SALSAEnactor(bool DEBUG = false) :
        EnactorBase(EDGE_FRONTIERS, DEBUG),
        done(NULL),
        d_done(NULL)
    {}

    /**
     * @brief SALSAEnactor destructor
     */
    virtual ~SALSAEnactor()
    {
    }

    template <typename ProblemData>
    void NormalizeRank(ProblemData *problem, CudaContext &context, int hub_or_auth, int nodes)
    {

        typedef typename ProblemData::Value         Value;
        Value *rank_curr;
        Value *rank_next;
        if (hub_or_auth == 0) {
            rank_curr = problem->data_slices[0]->d_hrank_curr;
            rank_next = problem->data_slices[0]->d_hrank_next;
            //printf("hub\n");
        } else {
            rank_curr = problem->data_slices[0]->d_arank_curr;
            rank_next = problem->data_slices[0]->d_arank_next;
            //printf("auth\n");
        }

        //swap rank_curr and rank_next
        util::MemsetCopyVectorKernel<<<128, 128>>>(rank_curr, rank_next, nodes); 

        util::MemsetKernel<<<128, 128>>>(rank_next, (Value)0.0, nodes);

        //util::DisplayDeviceResults(rank_curr, nodes);
    }

    /**
     * \addtogroup PublicInterface
     * @{
     */

    /**
     * @brief Obtain statistics about the last SALSA search enacted.
     *
     * @param[out] total_queued Total queued elements in SALSA kernel running.
     * @param[out] avg_duty Average kernel running duty (kernel run time/kernel lifetime).
     */
    void GetStatistics(
        long long &total_queued,
        double &avg_duty)
    {
        cudaThreadSynchronize();

        total_queued = enactor_stats.total_queued;
        
        avg_duty = (enactor_stats.total_lifetimes >0) ?
            double(enactor_stats.total_runtimes) / enactor_stats.total_lifetimes : 0.0;
    }

    /** @} */

    /**
     * @brief Enacts a SALSA computing on the specified graph.
     *
     * @tparam AdvanceKernelPolicy Kernel policy for advance
     * @tparam FilterKernelPolicy Kernel policy for filter
     * @tparam SALSAProblem SALSA Problem type.
     *
     * @param[in] problem SALSAProblem object.
     * @param[in] max_iteration Max number of iterations of SALSA algorithm
     * @param[in] max_grid_size Max grid size for SALSA kernel calls.
     *
     * \return cudaError_t object which indicates the success of all CUDA function calls.
     */
    template<
        typename AdvanceKernelPolicy,
        typename FilterKernelPolicy,
        typename SALSAProblem>
    cudaError_t EnactSALSA(
    CudaContext                         &context,
    SALSAProblem                        *problem,
    typename SALSAProblem::SizeT        max_iteration,
    int                                 max_grid_size = 0)
    {
        typedef typename SALSAProblem::SizeT       SizeT;
        typedef typename SALSAProblem::VertexId    VertexId;
        typedef typename SALSAProblem::Value       Value;

        typedef HFORWARDFunctor<
            VertexId,
            SizeT,
            Value,
            SALSAProblem> HForwardFunctor;

        typedef AFORWARDFunctor<
            VertexId,
            SizeT,
            Value,
            SALSAProblem> AForwardFunctor;

        typedef HBACKWARDFunctor<
            VertexId,
            SizeT,
            Value,
            SALSAProblem> HBackwardFunctor;

        typedef ABACKWARDFunctor<
            VertexId,
            SizeT,
            Value,
            SALSAProblem> ABackwardFunctor;

        cudaError_t retval = cudaSuccess;

        unsigned int *d_scanned_edges = NULL;

        do {
            if (DEBUG) {
                printf("Iteration, Edge map queue, Vertex map queue\n");
                printf("0");
            }

            fflush(stdout);

            // Lazy initialization
            if (retval = Setup(problem)) break;

            if (retval = EnactorBase::Setup(max_grid_size,
                                            AdvanceKernelPolicy::CTA_OCCUPANCY,
                                            FilterKernelPolicy::CTA_OCCUPANCY))
                                            break;

            //graph slice
            typename SALSAProblem::GraphSlice *graph_slice = problem->graph_slices[0];
            typename SALSAProblem::DataSlice *data_slice = problem->d_data_slices[0];
            cudaChannelFormatDesc   row_offsets_desc = cudaCreateChannelDesc<SizeT>(); 

            frontier_attribute.queue_length     = graph_slice->nodes;
            frontier_attribute.queue_index      = 0;
            frontier_attribute.selector         = 0;

            frontier_attribute.queue_reset      = true;

            if (AdvanceKernelPolicy::ADVANCE_MODE == gunrock::oprtr::advance::LB) {
                if (retval = util::GRError(cudaMalloc(
                                (void**)&d_scanned_edges,
                                (graph_slice->edges+1) * sizeof(unsigned int)),
                                "SALSAProblem cudaMalloc d_scanned_edges failed", __FILE__, __LINE__)) return retval;
            }

            // Step through SALSA iterations 
            {

                /*if (retval = util::GRError(cudaBindTexture(
                    0,
                    gunrock::oprtr::edge_map_forward::RowOffsetTex<SizeT>::ref,
                    graph_slice->d_row_offsets,
                    row_offsets_desc,
                    (graph_slice->nodes + 1) * sizeof(SizeT)),
                        "SALSAEnactor cudaBindTexture row_offset_tex_ref failed", __FILE__, __LINE__)) break;*/


                util::MemsetIdxKernel<<<128, 128>>>(graph_slice->frontier_queues.d_keys[frontier_attribute.selector], graph_slice->nodes);

                if (retval = work_progress.SetQueueLength(frontier_attribute.queue_index, graph_slice->nodes)) break;
                // Edge Map
                gunrock::oprtr::advance::LaunchKernel<AdvanceKernelPolicy, SALSAProblem, HForwardFunctor>(
                    d_done,
                    enactor_stats,
                    frontier_attribute,
                    data_slice,
                    (VertexId*)NULL,
                    (bool*)NULL,
                    (bool*)NULL,
                    d_scanned_edges,
                    graph_slice->frontier_queues.d_keys[frontier_attribute.selector],               //d_in_queue
                    graph_slice->frontier_queues.d_keys[frontier_attribute.selector^1],             //d_out_queue
                    (VertexId*)NULL,    //d_pred_in_queue
                    (VertexId*)NULL,
                    graph_slice->d_row_offsets,
                    graph_slice->d_column_indices,
                    (SizeT*)NULL,
                    (VertexId*)NULL,
                    graph_slice->frontier_elements[frontier_attribute.selector],
                    graph_slice->frontier_elements[frontier_attribute.selector^1],
                    this->work_progress,
                    context,
                    gunrock::oprtr::advance::V2E);
                    

                if (DEBUG && (retval = util::GRError(cudaThreadSynchronize(), "edge_map_forward::Kernel failed", __FILE__, __LINE__))) break;

                /*if (retval = util::GRError(cudaBindTexture(
                                0,
                                gunrock::oprtr::edge_map_forward::RowOffsetTex<SizeT>::ref,
                                graph_slice->d_column_offsets,
                                row_offsets_desc,
                                (graph_slice->nodes + 1) * sizeof(SizeT)),
                            "SALSAEnactor cudaBindTexture row_offset_tex_ref failed", __FILE__, __LINE__)) break;*/

                // Edge Map
                gunrock::oprtr::advance::LaunchKernel<AdvanceKernelPolicy, SALSAProblem, AForwardFunctor>(
                    d_done,
                    enactor_stats,
                    frontier_attribute,
                    data_slice,
                    (VertexId*)NULL,
                    (bool*)NULL,
                    (bool*)NULL,
                    d_scanned_edges,
                    graph_slice->frontier_queues.d_keys[frontier_attribute.selector],               //d_in_queue
                    graph_slice->frontier_queues.d_keys[frontier_attribute.selector^1],             //d_out_queue
                    (VertexId*)NULL,    //d_pred_in_queue
                    (VertexId*)NULL,
                    graph_slice->d_column_offsets,
                    graph_slice->d_row_indices,
                    (SizeT*)NULL,
                    (VertexId*)NULL,
                    graph_slice->frontier_elements[frontier_attribute.selector],
                    graph_slice->frontier_elements[frontier_attribute.selector^1],
                    this->work_progress,
                    context,
                    gunrock::oprtr::advance::V2E);

                if (DEBUG && (retval = util::GRError(cudaThreadSynchronize(), "edge_map_forward::Kernel failed", __FILE__, __LINE__))) break;
            }

            //util::DisplayDeviceResults(problem->data_slices[0]->d_hub_predecessors, graph_slice->edges);
            //util::DisplayDeviceResults(problem->data_slices[0]->d_auth_predecessors, graph_slice->edges);

            frontier_attribute.queue_length     = graph_slice->edges;

            /*util::DisplayDeviceResults(graph_slice->d_column_offsets, graph_slice->nodes);
            util::DisplayDeviceResults(graph_slice->d_row_indices, graph_slice->edges);

            util::DisplayDeviceResults(graph_slice->d_row_offsets, graph_slice->nodes);
            util::DisplayDeviceResults(graph_slice->d_column_indices, graph_slice->edges);*/
            while (true) { 

                util::MemsetIdxKernel<<<128, 128>>>(graph_slice->frontier_queues.d_keys[frontier_attribute.selector], graph_slice->edges);

                /*if (retval = util::GRError(cudaBindTexture(
                    0,
                    gunrock::oprtr::edge_map_forward::RowOffsetTex<SizeT>::ref,
                    graph_slice->d_column_offsets,
                    row_offsets_desc,
                    (graph_slice->nodes + 1) * sizeof(SizeT)),
                        "SALSAEnactor cudaBindTexture row_offset_tex_ref failed", __FILE__, __LINE__)) break;*/

                frontier_attribute.queue_length     = graph_slice->edges;
                if (retval = work_progress.SetQueueLength(frontier_attribute.queue_index, frontier_attribute.queue_length)) break;
                // Edge Map
                gunrock::oprtr::advance::LaunchKernel<AdvanceKernelPolicy, SALSAProblem, HBackwardFunctor>(
                    d_done,
                    enactor_stats,
                    frontier_attribute,
                    data_slice,
                    (VertexId*)NULL,
                    (bool*)NULL,
                    (bool*)NULL,
                    d_scanned_edges,
                    graph_slice->frontier_queues.d_keys[frontier_attribute.selector],              // d_in_queue
                    graph_slice->frontier_queues.d_keys[frontier_attribute.selector^1],            // d_out_queue
                    (VertexId*)NULL,
                    (VertexId*)NULL,
                    graph_slice->d_column_offsets,
                    graph_slice->d_row_indices,
                    (SizeT*)NULL,
                    (VertexId*)graph_slice->d_column_indices,
                    graph_slice->nodes,//graph_slice->frontier_elements[frontier_attribute.selector],                   // max_in_queue
                    graph_slice->edges,//graph_slice->frontier_elements[frontier_attribute.selector^1]*10000,                 // max_out_queue
                    this->work_progress,
                    context,
                    gunrock::oprtr::advance::E2V,
                    true);

                if (DEBUG && (retval = util::GRError(cudaThreadSynchronize(), "edge_map_forward::Kernel failed", __FILE__, __LINE__))) break;

                //if (retval = work_progress.GetQueueLength(frontier_attribute.queue_index, frontier_attribute.queue_length)) break;
                //util::DisplayDeviceResults(graph_slice->frontier_queues.d_keys[frontier_attribute.selector], frontier_attribute.queue_length); 


                NormalizeRank<SALSAProblem>(problem, context, 0, graph_slice->nodes);

                /*if (retval = util::GRError(cudaBindTexture(
                    0,
                    gunrock::oprtr::edge_map_forward::RowOffsetTex<SizeT>::ref,
                    graph_slice->d_row_offsets,
                    row_offsets_desc,
                    (graph_slice->nodes + 1) * sizeof(SizeT)),
                        "SALSAEnactor cudaBindTexture row_offset_tex_ref failed", __FILE__, __LINE__)) break;*/

                // Edge Map
                gunrock::oprtr::advance::LaunchKernel<AdvanceKernelPolicy, SALSAProblem, ABackwardFunctor>(
                    d_done,
                    enactor_stats,
                    frontier_attribute,
                    data_slice,
                    (VertexId*)NULL,
                    (bool*)NULL,
                    (bool*)NULL,
                    d_scanned_edges,
                    graph_slice->frontier_queues.d_keys[frontier_attribute.selector],              // d_in_queue
                    graph_slice->frontier_queues.d_keys[frontier_attribute.selector^1],            // d_out_queue
                    (VertexId*)NULL,
                    (VertexId*)NULL,
                    graph_slice->d_row_offsets,
                    graph_slice->d_column_indices,
                    (SizeT*)NULL,
                    (VertexId*)graph_slice->d_row_indices,
                    graph_slice->nodes,//graph_slice->frontier_elements[frontier_attribute.selector],                   // max_in_queue
                    graph_slice->edges,//graph_slice->frontier_elements[frontier_attribute.selector^1]*10000,                 // max_out_queue
                    this->work_progress,
                    context,
                    gunrock::oprtr::advance::E2V,
                    true);

                if (DEBUG && (retval = util::GRError(cudaThreadSynchronize(), "edge_map_forward::Kernel failed", __FILE__, __LINE__))) break;

                if (DEBUG) {
                    if (retval = work_progress.GetQueueLength(frontier_attribute.queue_index, frontier_attribute.queue_length)) break;
                    printf(", %lld", (long long)frontier_attribute.queue_length);
                }

                if (INSTRUMENT) {
                    if (retval = enactor_stats.advance_kernel_stats.Accumulate(
                        enactor_stats.advance_grid_size,
                        enactor_stats.total_runtimes,
                        enactor_stats.total_lifetimes)) break;
                }

                NormalizeRank<SALSAProblem>(problem, context, 1, graph_slice->nodes); 
                
                
                enactor_stats.iteration++; 

                if (enactor_stats.iteration >= max_iteration) break;

                if (DEBUG) printf("\n%lld", (long long) enactor_stats.iteration);
            
            }

            if (retval) break;

            //Check overflow ignored here

        } while(0);

        if (DEBUG) printf("\nGPU SALSA Done.\n");
        return retval;
    }

    /**
     * \addtogroup PublicInterface
     * @{
     */

    /**
     * @brief SALSA Enact kernel entry.
     *
     * @tparam SALSAProblem SALSA Problem type. @see SALSAProblem
     *
     * @param[in] problem Pointer to SALSAProblem object.
     * @param[in] src Source node for SALSA.
     * @param[in] max_grid_size Max grid size for SALSA kernel calls.
     *
     * \return cudaError_t object which indicates the success of all CUDA function calls.
     */
    template <typename SALSAProblem>
    cudaError_t Enact(
        CudaContext                          &context,
        SALSAProblem                        *problem,
        typename SALSAProblem::SizeT       max_iteration,
        int                             max_grid_size = 0)
    {
        if (this->cuda_props.device_sm_version >= 300) {
            typedef gunrock::oprtr::filter::KernelPolicy<
                SALSAProblem,                         // Problem data type
            300,                                // CUDA_ARCH
            INSTRUMENT,                         // INSTRUMENT
            0,                                  // SATURATION QUIT
            true,                               // DEQUEUE_SALSAOBLEM_SIZE
            8,                                  // MIN_CTA_OCCUPANCY
            6,                                  // LOG_THREADS
            1,                                  // LOG_LOAD_VEC_SIZE
            0,                                  // LOG_LOADS_PER_TILE
            5,                                  // LOG_RAKING_THREADS
            5,                                  // END_BITMASK_CULL
            8>                                  // LOG_SCHEDULE_GRANULARITY
                FilterKernelPolicy;

            typedef gunrock::oprtr::advance::KernelPolicy<
                SALSAProblem,                         // Problem data type
                300,                                // CUDA_ARCH
                INSTRUMENT,                         // INSTRUMENT
                1,                                  // MIN_CTA_OCCUPANCY
                10,                                  // LOG_THREADS
                8,                                  // LOG_BLOCKS
                32*128,                                  // LIGHT_EDGE_THRESHOLD (used for partitioned advance mode)
                1,                                  // LOG_LOAD_VEC_SIZE
                0,                                  // LOG_LOADS_PER_TILE
                5,                                  // LOG_RAKING_THREADS
                32,                            // WARP_GATHER_THRESHOLD
                128 * 4,                            // CTA_GATHER_THRESHOLD
                7,                                  // LOG_SCHEDULE_GRANULARITY
                gunrock::oprtr::advance::LB>
                    AdvanceKernelPolicy;

            return EnactSALSA<AdvanceKernelPolicy, FilterKernelPolicy, SALSAProblem>(
                    context, problem, max_iteration, max_grid_size);
        }

        //to reduce compile time, get rid of other architecture for now
        //TODO: add all the kernelpolicy settings for all archs

        printf("Not yet tuned for this architecture\n");
        return cudaErrorInvalidDeviceFunction;
    }

    /** @} */

};

} // namespace salsa
} // namespace app
} // namespace gunrock

// Leave this at the end of the file
// Local Variables:
// mode:c++
// c-file-style: "NVIDIA"
// End:
