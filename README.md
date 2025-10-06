## Voxel Engine with Odin+Metal

This is my playground for learning mesh shader pipelines applied to a voxel engine.

As of right now it's mostly empty, so if you came here looking for a nice example, you won't have much luck yet.

#### To Do:
 - Write a proper first person camera
 - Write an Object Shader and dispatch clusters of voxels. What exacly the cluster will be is yet TBD. 
 - Define a Contree data structure (like octree but 8x8x8 instead of 2x2x2)
 - Compare the above with an octree with leafs of 32x32xuint32 with bit operations, see which one wins.
 - Do some culling on the object shader
 - Do triangle level culling on the mesh shader. Since voxels will always be on a grid, there is a finite and small number of easy culling to do for a given voxel (without taking occlusion into consideration yet)
 - Work on lights before starting with materials:
    - Idea: Try an Immediate Radiance kind of approach, maybe keep a cache of luminosity on each visible voxel. That could even be done on CPU threads. I don't know.
    - I still need to decide if I'm going with a per voxel light, per face light, or something more detailed.


References:
 - Some Metal examples https://github.com/chaoticbob/GraphicsExperiments/blob/main/projects/geometry/113_mesh_shader_instancing_metal/113_mesh_shader_instancing_metal.cpp
 - Blog on Mesh Shaders, mostly for NVidia and AMD https://timur.hu/blog/2022/mesh-and-task-shaders
 - [Advanced Mesh Shaders | Martin Fuller | DirectX Developer Day](https://www.youtube.com/watch?v=0sJ_g-aWriQ)
 - [Modern Renedering Introduction](https://alelievr.github.io/Modern-Rendering-Introduction/MeshShaders/)

 
