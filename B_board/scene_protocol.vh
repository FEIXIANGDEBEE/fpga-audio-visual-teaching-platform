`ifndef SCENE_PROTOCOL_VH
`define SCENE_PROTOCOL_VH
`define SCENE_HELLO       8'h01
`define SCENE_DESCRIPTOR  8'h02
`define SCENE_IMAGE_REQ   8'h10
`define SCENE_IMAGE_DATA  8'h11
`define SCENE_IMAGE_ACK   8'h12
`define SCENE_IMAGE_RETRY 8'h13
`define SCENE_PREPARE     8'h20
`define SCENE_READY       8'h21
`define SCENE_COMMIT      8'h22
`define SCENE_APPLIED     8'h23
`define SCENE_ERROR       8'h24
`define SCENE_CONTROL     8'h30
`define SCENE_WITNESS     8'h31
`define SCENE_SPECTRUM    8'h32
`define SCENE_HEARTBEAT   8'h33
`define SCENE_HELLO_REQUEST    8'd1
`define SCENE_HELLO_OFFER      8'd2
`define SCENE_HELLO_ACCEPT     8'd3
`define SCENE_HELLO_RUNNING    8'd4
`define SCENE_HELLO_CALIBRATED  8'd5
`endif
