## Voxel Engine with Odin+Metal

This is my playground for learning mesh shader pipelines applied to a voxel engine.

As of right it's just a mess, so if you came here looking for a nice example, you won't have much luck yet.

#### To Do:
 - Model the voxels with a Z-Order Curve (Morton encoding) Octree 
 - Do some culling on the object shader
 - Decide on the actual rendering techniques and style. Per voxel or full path traced? Radiance Cascade maybe?
 - Decouple world updates from renderer and improve input

#### To NOT Do:
 - There will be no temporal amortization.
 - There will be no upscaling tricks (unless we can ensure certain level of quality).
 - No hardware raytracing will be used.

References:
 - [Voxel Compression](https://eisenwave.github.io/voxel-compression-docs/) 
 - [Metal by Example](https://metalbyexample.com/mesh-shaders/)
 - Some Metal examples https://github.com/chaoticbob/GraphicsExperiments/blob/main/projects/geometry/113_mesh_shader_instancing_metal/113_mesh_shader_instancing_metal.cpp
 - Blog on Mesh Shaders, mostly for NVidia and AMD https://timur.hu/blog/2022/mesh-and-task-shaders
 - [Advanced Mesh Shaders | Martin Fuller | DirectX Developer Day](https://www.youtube.com/watch?v=0sJ_g-aWriQ)
 - [Modern Renedering Introduction](https://alelievr.github.io/Modern-Rendering-Introduction/MeshShaders/)

 
Other people making voxel engines:
 - https://www.youtube.com/@DouglasDwyer
 - https://www.youtube.com/@GabeRundlett