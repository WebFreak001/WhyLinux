module game.game;

import erupted;

import game.vulkan.context;
import game.vulkan.mesh;
import game.vulkan.window;
import game.vulkan.wrap;

import gl3n.linalg;
import gl3n.math;

import dmech.geometry;
import dmech.rigidbody;
import dmech.world;
import dlib.core.memory;
import dlib.math.vector : Vector3f;
import dlib.math.matrix : Matrix4x4f;

public enum real PI_OVER_2 = PI / 2.0;

import glfw3d;

class GameWindow : VulkanWindow {
	PhysicsWorld world;
	RigidBody bPlayer;

	this(int width, int height) {
		super(width, height, "WhyLinux");

		setInputMode(GLFW_CURSOR, GLFW_CURSOR_DISABLED);

		world = New!PhysicsWorld();
		world.gravity = Vector3f(0, 0, -9.8f);

		RigidBody bGround = world.addStaticBody(Vector3f(0, 0, -1));
		Geometry gGround = New!GeomBox(Vector3f(100.0f, 100.0f, 1.0f));
		world.addShapeComponent(bGround, gGround, Vector3f(0, 0, 0), 1.0f);

		bPlayer = world.addDynamicBody(Vector3f(0, 0, 10), 800);
		bPlayer.enableRotation = false;
		Geometry gPlayer = New!GeomEllipsoid(Vector3f(0.3f, 0.3f, 0.9f));
		world.addShapeComponent(bPlayer, gPlayer, Vector3f(0, 0, 0), 1.0f);
	}

	~this() {
		Delete(world);
	}

	Mesh!PositionNormalTexCoordVertex meshObject;
	VkImage textureImage;
	VkImageView textureImageView;
	VkSampler textureSampler;
	VkDeviceMemory textureImageMemory;
	VkBuffer uniformBuffer;
	VkDeviceMemory uniformBufferMemory;
	VkDescriptorSet descriptorSet;

	void createTextures() {
		import imageformats;

		auto image = read_image("textures/dman.jpg", ColFmt.RGBA);

		VkDeviceSize imageSize = image.w * image.h * 4;

		VkBuffer stagingBuffer;
		VkDeviceMemory stagingBufferMemory;
		context.createTransferSrcBuffer(imageSize, stagingBuffer, stagingBufferMemory);
		context.fillGPUMemory(stagingBufferMemory, 0, image.pixels);

		context.createImage(image.w, image.h, VK_FORMAT_R8G8B8A8_UNORM, VK_IMAGE_TILING_OPTIMAL,
				VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_SAMPLED_BIT,
				VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, textureImage, textureImageMemory);

		disposer.register(textureImage, textureImageMemory);

		context.transitionImageLayout(textureImage, VK_FORMAT_R8G8B8A8_UNORM,
				VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
		context.copyBufferToImage(stagingBuffer, textureImage, image.w, image.h);
		context.transitionImageLayout(textureImage, VK_FORMAT_R8G8B8A8_UNORM,
				VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);

		device.DestroyBuffer(stagingBuffer, context.pAllocator);
		device.FreeMemory(stagingBufferMemory, context.pAllocator);

		textureImageView = context.createImageView(textureImage, VK_FORMAT_R8G8B8A8_UNORM);
		context.disposer.register!"DestroyImageView"(textureImageView);

		VkSamplerCreateInfo samplerInfo = context.hqSamplerInfo;
		device.CreateSampler(&samplerInfo, context.pAllocator, &textureSampler)
			.enforceVK("vkCreateSampler");
		context.disposer.register!"DestroySampler"(textureSampler);
	}

	void loadMesh() {
		import std.algorithm;
		import std.conv;
		import std.stdio;
		import std.string;

		string mesh = "meshes/house.obj";
		vec3[] vecPool;
		vec3[] nrmPool;
		vec2[] texPool;

		ushort[3][] addedVerts;

		foreach (line; File(mesh).byLine) {
			auto parts = line.splitter;
			if (parts.empty)
				continue;
			if (parts.front == "v") {
				parts.popFront;
				vec3 v;
				v.x = parts.front.to!float;
				parts.popFront;
				v.y = parts.front.to!float;
				parts.popFront;
				v.z = parts.front.to!float;
				vecPool ~= v;
			}
			else if (parts.front == "vn") {
				parts.popFront;
				vec3 v;
				v.x = parts.front.to!float;
				parts.popFront;
				v.y = parts.front.to!float;
				parts.popFront;
				v.z = parts.front.to!float;
				nrmPool ~= v;
			}
			else if (parts.front == "vt") {
				parts.popFront;
				vec2 v;
				v.x = parts.front.to!float;
				parts.popFront;
				v.y = parts.front.to!float;
				texPool ~= v;
			}
			else if (parts.front == "f") {
				parts.popFront;
				foreach (part; parts) {
					auto ind = part.splitter('/');
					auto i1s = ind.front;
					ind.popFront;
					auto i2s = ind.front;
					ind.popFront;
					auto i3s = ind.front;
					ushort i1, i2, i3;
					if (i1s.empty)
						i1 = 0;
					else
						i1 = i1s.to!ushort;
					if (i2s.empty)
						i2 = 0;
					else
						i2 = i2s.to!ushort;
					if (i3s.empty)
						i3 = 0;
					else
						i3 = i3s.to!ushort;
					ushort[3] index = [i1, i2, i3];
					auto existing = addedVerts.countUntil(index);
					if (existing == -1) {
						meshObject.indices ~= cast(ushort) meshObject.vertices.length;
						meshObject.vertices ~= PositionNormalTexCoordVertex(vecPool[i1 - 1],
								nrmPool[i3 - 1], texPool[i2 - 1]);
					}
					else {
						meshObject.indices ~= cast(ushort) existing;
					}
				}
			}
		}
	}

	void createMeshBuffers() {
		loadMesh();

		meshObject.create(context);

		VkDeviceSize uniformBufferSize = UniformBufferObject.sizeof;
		createBuffer(context, uniformBufferSize, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
				VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
				uniformBuffer, uniformBufferMemory);
		disposer.register(uniformBuffer, uniformBufferMemory);
	}

	void createDescriptorSetLayout() {
		VkDescriptorSetLayoutBinding uniformsLayoutBinding;
		uniformsLayoutBinding.binding = 0;
		uniformsLayoutBinding.descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
		uniformsLayoutBinding.descriptorCount = 1;
		uniformsLayoutBinding.stageFlags = VK_SHADER_STAGE_VERTEX_BIT;
		uniformsLayoutBinding.pImmutableSamplers = null;

		VkDescriptorSetLayoutBinding samplerLayoutBinding;
		samplerLayoutBinding.binding = 1;
		samplerLayoutBinding.descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
		samplerLayoutBinding.descriptorCount = 1;
		samplerLayoutBinding.stageFlags = VK_SHADER_STAGE_FRAGMENT_BIT;
		samplerLayoutBinding.pImmutableSamplers = null;

		VkDescriptorSetLayoutBinding[2] bindings = [uniformsLayoutBinding, samplerLayoutBinding];

		VkDescriptorSetLayoutCreateInfo layoutInfo;
		layoutInfo.bindingCount = cast(uint) bindings.length;
		layoutInfo.pBindings = bindings.ptr;

		context.device.CreateDescriptorSetLayout(&layoutInfo, context.pAllocator,
				&context.descriptorSetLayout);
		disposer.register!"DestroyDescriptorSetLayout"(context.descriptorSetLayout);
	}

	override void createDescriptorSet() {
		VkDescriptorSetAllocateInfo allocInfo;
		allocInfo.descriptorPool = context.descriptorPool;
		allocInfo.descriptorSetCount = 1;
		allocInfo.pSetLayouts = &context.descriptorSetLayout;

		device.AllocateDescriptorSets(&allocInfo, &descriptorSet)
			.enforceVK("vkAllocateDescriptorSets");

		VkDescriptorBufferInfo bufferInfo;
		bufferInfo.buffer = uniformBuffer;
		bufferInfo.offset = 0;
		bufferInfo.range = UniformBufferObject.sizeof;

		VkDescriptorImageInfo imageInfo;
		imageInfo.imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
		imageInfo.imageView = textureImageView;
		imageInfo.sampler = textureSampler;

		VkWriteDescriptorSet[2] writeDescriptors;

		writeDescriptors[0].dstSet = descriptorSet;
		writeDescriptors[0].dstBinding = 0;
		writeDescriptors[0].dstArrayElement = 0;
		writeDescriptors[0].descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
		writeDescriptors[0].descriptorCount = 1;
		writeDescriptors[0].pBufferInfo = &bufferInfo;

		writeDescriptors[1].dstSet = descriptorSet;
		writeDescriptors[1].dstBinding = 1;
		writeDescriptors[1].dstArrayElement = 0;
		writeDescriptors[1].descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
		writeDescriptors[1].descriptorCount = 1;
		writeDescriptors[1].pImageInfo = &imageInfo;

		device.UpdateDescriptorSets(cast(uint) writeDescriptors.length, writeDescriptors.ptr, 0, null);
	}

	override void onLoad() {
		createTextures();
		createMeshBuffers();
		createDescriptorSet();
	}

	CursorPosition prevCursor = CursorPosition(0, 0);
	double yaw = 0, pitch = 0;
	bool prevSpace;
	override void onUpdate(double delta) {
		world.update(delta);

		auto cursor = getCursorPosition();
		double dx = cursor.x - prevCursor.x;
		double dy = cursor.y - prevCursor.y;
		prevCursor = cursor;

		yaw += dx * 7 * delta;
		pitch += dy * 7 * delta;

		if (pitch < -cradians!180)
			pitch = -cradians!180;
		else if (pitch > cradians!0)
			pitch = cradians!0;

		Vector3f input = Vector3f(0, 0, 0);
		if (getKey(GLFW_KEY_W) == GLFW_PRESS)
			input += Vector3f(sin(yaw), cos(yaw), 0);
		if (getKey(GLFW_KEY_A) == GLFW_PRESS)
			input += Vector3f(-cos(yaw), sin(yaw), 0);
		if (getKey(GLFW_KEY_S) == GLFW_PRESS)
			input += Vector3f(-sin(yaw), -cos(yaw), 0);
		if (getKey(GLFW_KEY_D) == GLFW_PRESS)
			input += Vector3f(cos(yaw), -sin(yaw), 0);
		if (getKey(GLFW_KEY_SPACE) == GLFW_PRESS && !prevSpace && bPlayer.linearVelocity.z <= 2)
			bPlayer.linearVelocity.z += 10;
		prevSpace = getKey(GLFW_KEY_SPACE) == GLFW_PRESS;

		Vector3f floorVelocity = Vector3f(0, 0, 0);

		if (input.lengthsqr > 0)
			bPlayer.linearVelocity += input.normalized * 35 * delta;

		float movementLoss = pow(0.005, delta);
		bPlayer.linearVelocity.x = (bPlayer.linearVelocity.x - floorVelocity.x) * movementLoss + floorVelocity.x;
		bPlayer.linearVelocity.y = (bPlayer.linearVelocity.y - floorVelocity.y) * movementLoss + floorVelocity.y;

		auto position = bPlayer.shapes[0].transformation.getColumn(3);

		UniformBufferObject uniforms;
		uniforms.model = mat4.identity;
		uniforms.view = mat4.xrotation(pitch) * mat4.zrotation(yaw) * mat4.translation(
				-position.x, -position.y, -position.z) * mat4.translation(0, 0, -0.3);
		uniforms.projection = mat4.perspective(width, height, 60, 0.1f, 100.0f);
		uniforms.projection[1][1] *= -1;

		uniforms.model.transpose();
		uniforms.view.transpose();
		uniforms.projection.transpose();

		uniforms.light = uniforms.model.inverse;

		context.fillGPUMemory(uniformBufferMemory, 0, uniforms);
	}

	override void onBuildRenderpass(VkCommandBuffer commandBuffer) {
		meshObject.bind(commandBuffer);

		context.device.vkCmdBindDescriptorSets(commandBuffer, VK_PIPELINE_BIND_POINT_GRAPHICS,
				context.pipelineLayout, 0, 1, &descriptorSet, 0, null);

		context.device.vkCmdDrawIndexed(commandBuffer, cast(uint) meshObject.indices.length, 1, 0, 0, 0);
	}
}
