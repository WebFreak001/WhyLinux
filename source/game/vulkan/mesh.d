module game.vulkan.mesh;

import erupted;

import gl3n.linalg;

struct Vertex {
	vec2 pos;
	vec3 color;
	vec2 texCoord;

	static VkVertexInputBindingDescription bindingDescription() {
		VkVertexInputBindingDescription desc;
		desc.binding = 0;
		desc.stride = typeof(this).sizeof;
		desc.inputRate = VK_VERTEX_INPUT_RATE_VERTEX;
		return desc;
	}

	static auto attributeDescriptions() {
		VkVertexInputAttributeDescription[3] ret;

		ret[0].binding = 0;
		ret[0].location = 0;
		ret[0].format = VK_FORMAT_R32G32_SFLOAT;
		ret[0].offset = 0;

		ret[1].binding = 0;
		ret[1].location = 1;
		ret[1].format = VK_FORMAT_R32G32B32_SFLOAT;
		ret[1].offset = pos.sizeof;

		ret[2].binding = 0;
		ret[2].location = 2;
		ret[2].format = VK_FORMAT_R32G32_SFLOAT;
		ret[2].offset = pos.sizeof + color.sizeof;

		return ret;
	}
}
