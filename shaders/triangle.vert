#version 450
#extension GL_ARB_separate_shader_objects : enable

layout(binding = 0) uniform UniformBufferObject {
	// keep in sync with context.d
	mat4 model, view, projection, light;
} uniforms;

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec3 inNormal;
layout(location = 2) in vec2 inTexCoord;

layout(location = 0) out vec3 fragNormal;
layout(location = 1) out vec2 fragTexCoord;

out gl_PerVertex {
	vec4 gl_Position;
};

void main() {
	gl_Position = uniforms.projection * uniforms.view * uniforms.model * vec4(inPosition, 1.0);
	fragNormal = (uniforms.light * vec4(inNormal, 0.0)).xyz;
	fragTexCoord = inTexCoord;
}