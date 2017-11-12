module game.vulkan.mesh;

import erupted;

import gl3n.linalg;

import game.vulkan.context;
import game.vulkan.wrap;

import std.traits;
import std.meta;

template isVariable(alias A) {
	enum isVariable = !isCallable!A;
}

template isVariable(A) {
	enum isVariable = false;
}

private string[] accessibleProperties(T)() {
	string[] ret;
	foreach (i, member; __traits(allMembers, T)) {
		static if (isVariable!(mixin("T.init." ~ member)) && __traits(compiles, {
				alias U = typeof(mixin("T.init." ~ member));
			})) {
			ret ~= member;
		}
	}
	return ret;
}

mixin template VertexBase() {
	static VkVertexInputBindingDescription bindingDescription() {
		VkVertexInputBindingDescription desc;
		desc.binding = 0;
		desc.stride = typeof(this).sizeof;
		desc.inputRate = VK_VERTEX_INPUT_RATE_VERTEX;
		return desc;
	}

	static auto attributeDescriptions() {
		enum properties = accessibleProperties!(typeof(this));
		enum n = properties.length;
		VkVertexInputAttributeDescription[n] ret;

		uint offset = 0;
		foreach (i, member; aliasSeqOf!properties) {
			ret[i].binding = 0;
			ret[i].location = cast(uint) i;
			alias T = typeof(mixin(member));
			static if (getUDAs!(mixin(member), VkFormat).length > 0)
				ret[i].format = getUDAs!(mixin(member), VkFormat)[0];
			else static if (is(T == float))
				ret[i].format = VK_FORMAT_R32_SFLOAT;
			else static if (is(T == vec2))
				ret[i].format = VK_FORMAT_R32G32_SFLOAT;
			else static if (is(T == vec3))
				ret[i].format = VK_FORMAT_R32G32B32_SFLOAT;
			else static if (is(T == vec4))
				ret[i].format = VK_FORMAT_R32G32B32A32_SFLOAT;
			else static if (is(T == vec2i))
				ret[i].format = VK_FORMAT_R32G32_SINT;
			else static if (is(T == vec3i))
				ret[i].format = VK_FORMAT_R32G32B32_SINT;
			else static if (is(T == vec4i))
				ret[i].format = VK_FORMAT_R32G32B32A32_SINT;
			else
				static assert(false, "Invalid member type, annotate with a VkFormat to assign format");
			ret[i].offset = offset;
			offset += mixin(member).sizeof;
		}

		return ret;
	}
}

struct Position2DTexCoordVertex {
	vec2 pos;
	vec2 texCoord;

	mixin VertexBase;
}

struct PositionNormalTexCoordVertex {
	vec3 pos;
	vec3 normal;
	vec2 texCoord;

	mixin VertexBase;
}

struct PositionColorTexCoordVertex {
	vec3 pos;
	vec4 color;
	vec2 texCoord;

	mixin VertexBase;
}

struct Mesh(Vertex, Index = ushort) {
	static assert(is(Index == ushort) || is(Index == uint));

	Vertex[] vertices;
	Index[] indices;

	VkBuffer buffer;
	VkDeviceMemory bufferMemory;

	private VulkanContext* context;
	private VkDeviceSize indexOffset;
	private PAllocators allocators;

	~this() {
		destroy();
	}

	void destroy() {
		if (buffer) {
			context.device.DestroyBuffer(buffer, allocators);
			context.device.FreeMemory(bufferMemory, allocators);

			buffer = null;
			bufferMemory = null;
		}
	}

	void create(ref VulkanContext context) {
		this.context = &context;

		allocators = context.pAllocator;

		VkDeviceSize verticesSize = indexOffset = vertices.length * Vertex.sizeof;
		VkDeviceSize indicesSize = indices.length * Index.sizeof;
		VkDeviceSize bufferSize = verticesSize + indicesSize;

		createBuffer(context, bufferSize,
				VK_BUFFER_USAGE_TRANSFER_DST_BIT | VK_BUFFER_USAGE_VERTEX_BUFFER_BIT | VK_BUFFER_USAGE_INDEX_BUFFER_BIT,
				VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, buffer, bufferMemory);

		// TODO: better memory management not creating a new command buffer every time

		VkBuffer stagingBuffer;
		VkDeviceMemory stagingBufferMemory;
		context.createTransferSrcBuffer(bufferSize, stagingBuffer, stagingBufferMemory);

		context.fillGPUMemory!((void[] data) {
			data[0 .. verticesSize] = cast(void[]) vertices;
			data[verticesSize .. verticesSize + indicesSize] = cast(void[]) indices;
		})(stagingBufferMemory, bufferSize);

		copyBufferSync(context, stagingBuffer, buffer, bufferSize);

		context.device.DestroyBuffer(stagingBuffer, context.pAllocator);
		context.device.FreeMemory(stagingBufferMemory, context.pAllocator);
	}

	void bind(VkCommandBuffer commandBuffer) {
		VkDeviceSize vertexOffset = 0;
		context.device.vkCmdBindVertexBuffers(commandBuffer, 0, 1, &buffer, &vertexOffset);

		context.device.vkCmdBindIndexBuffer(commandBuffer, buffer, indexOffset,
				is(Index == ushort) ? VK_INDEX_TYPE_UINT16 : VK_INDEX_TYPE_UINT32);
	}
}
