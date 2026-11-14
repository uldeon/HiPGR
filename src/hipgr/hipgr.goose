// HiPGR - High Performance Goose Renderer: public entry point.
//
// Import this package and nothing else:
//
//   import hipgr from "../src/hipgr";
//
// Every public name lives in namespace hipgr. The modules it re-exports are
// organised by responsibility:
//
//   handle    public handle encoding and generations
//   state     pipeline and sampler state, as data
//   math      Mat4 and the transforms applications build
//   gpu       the backend boundary: the only module issuing backend calls
//   device    Device, resource records, handle validation, lifetime
//   mesh      Vertex, Mesh, 16- and 32-bit indexing, built-in geometry
//   image     Image: RGBA8 textures
//   camera    Camera and projections
//   material  Shader, MaterialDesc, the built-in shaders, lights
//   uniforms  the std140 uniform blocks, shared by the passes and shaders
//   post      the shadow, scene, bloom and composite passes
//   renderer  frame lifecycle and draw submission
//   platform  keys, mouse, clock
//
// This is a renderer, not a game engine: see ROADMAP.md for what each milestone
// adds and PROGRESS.md for what is actually verified.
namespace hipgr;

import .handle;
import .state;
import .math;
import .gpu;
import .device;
import .mesh;
import .camera;
import .image;
import .material;
import .uniforms;
import .post;
import .renderer;
import .platform;

fn version() -> u8[:] { "0.6.0" }
