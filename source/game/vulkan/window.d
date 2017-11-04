module game.vulkan.window;

import glfw3d;

class VulkanWindow : Window {
	this(int width, int height, string name) {
		glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
		glfwWindowHint(GLFW_RESIZABLE, GLFW_FALSE);
		super(width, height, name);
	}
}
