// 1 Transformer PKG
//
// transformer_pkg.sv
package transformer_pkg;
    // Parameters defaults; override when instantiating
    parameter int SEQ      = 16;
    parameter int EMB      = 64;
    parameter int HEADS    = 8;
    parameter int HEAD_DIM = EMB/HEADS;
    parameter int FF_DIM   = EMB*4;
    parameter int DATA_W   = 16; // bit width for fixed point / integer data

    // Types
    typedef logic signed [DATA_W-1:0] data_t;
    // vector types
    typedef data_t vec_emb_t [EMB];
    typedef data_t vec_head_t [HEAD_DIM];
    typedef data_t seq_emb_t [SEQ][EMB];
    typedef data_t seq_head_t [SEQ][HEAD_DIM];

endpackage

