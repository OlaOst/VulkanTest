import std.algorithm : all, any, each, map;
import std.stdio : writeln;

import derelict.sdl2.sdl;
import erupted;


private void checkVk(VkResult result)
{
  import std.conv : to;
  import std.exception : enforce;
  enforce(result == VK_SUCCESS, result.to!string);
}

VkInstance createVulkanInstance(string[] requestedValidationLayers)
{
  DerelictErupted.load();

  VkApplicationInfo appInfo =
  {
    sType: VK_STRUCTURE_TYPE_APPLICATION_INFO,
    pApplicationName: "Vulkan Test",
    applicationVersion: VK_MAKE_VERSION(1, 0, 0),
    pEngineName: "No engine",
    engineVersion: VK_MAKE_VERSION(1, 0, 0),
    apiVersion: VK_API_VERSION_1_0,
  };
  
  VkInstanceCreateInfo createInfo =
  {
    sType: VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
    pApplicationInfo: &appInfo,
    
    //enabledExtensionCount: ?,
    //ppEnableExtensionNames: ?,    
  };

  debug
  {
    createInfo.enabledLayerCount = cast(uint)requestedValidationLayers.length;
    import std.array : array;
    import std.string : toStringz;
    createInfo.ppEnabledLayerNames = requestedValidationLayers.map!(layer => layer.toStringz).array.ptr;
  }
  else
  {
    createInfo.enabledLayerCount = 0;
  }

  
  VkInstance instance;
  vkCreateInstance(&createInfo, null, &instance).checkVk;

  return instance;
}

VkExtensionProperties[] getExtensions(VkInstance instance)
{  
  uint extensionCount;
  vkEnumerateInstanceExtensionProperties(null, &extensionCount, null).checkVk;
    
  VkExtensionProperties[] extensions;
  extensions.length = extensionCount;
  vkEnumerateInstanceExtensionProperties(null, &extensionCount, extensions.ptr).checkVk;
  
  return extensions;
}

VkLayerProperties[] getAvailableLayers(VkInstance instance)
{
  uint layerCount;
  vkEnumerateInstanceLayerProperties(&layerCount, null).checkVk;
  
  VkLayerProperties[] availableLayers;
  availableLayers.length = layerCount;
  
  vkEnumerateInstanceLayerProperties(&layerCount, availableLayers.ptr).checkVk;
  
  return availableLayers;
}

bool checkValidationLayerSupport(VkInstance instance, string[] requestedValidationLayers)
{
  auto availableValidationLayers = instance.getAvailableLayers();
  return requestedValidationLayers.all!(requestedValidationLayerName => availableValidationLayers.any!(availableValidationLayer => requestedValidationLayerName == availableValidationLayer.layerName));
}

SDL_Window* createSDLWindow()
{
  DerelictSDL2.load(SharedLibVersion(2, 0, 4));
  
  import std.conv : to;
  import std.exception : enforce;
  enforce(SDL_Init(SDL_INIT_VIDEO) == 0, "Failed to initialize SDL: " ~ SDL_GetError().to!string);
  
  auto window = SDL_CreateWindow("VulkanTest",
                                 SDL_WINDOWPOS_CENTERED,
                                 SDL_WINDOWPOS_CENTERED,
                                 800,
                                 600,
                                 SDL_WINDOW_SHOWN);

  enforce(window !is null, "Error creating window: " ~ SDL_GetError().to!string);
  
  SDL_SysWMinfo info;
  //SDL_VERSION(&info.version_); // compiled version
  SDL_GetVersion(&info.version_); // linked version
  enforce(SDL_GetWindowWMInfo(window, &info) != SDL_FALSE, "Failed to get window info from SDL: " ~ SDL_GetError().to!string);  
  
  return window;
}

void main()
{
  auto window = createSDLWindow();
  
  //auto requestedValidationLayers = ["VK_LAYER_LUNARG_standard_validation"];
  // TODO: no vulkan validation layers on my box yet, so let's not request any for now
  string[] requestedValidationLayers = [];
  auto instance = createVulkanInstance(requestedValidationLayers);
    
  writeln("Extensions:");
  instance.getExtensions.map!(ext => ext.extensionName).each!writeln;

  debug
  {
    import std.exception : enforce;
    import std.conv : to;
    enforce(instance.checkValidationLayerSupport(requestedValidationLayers),
            "Could not find requested validation layers " ~ requestedValidationLayers.to!string ~ " in available layers " ~ instance.getAvailableLayers().to!string);
  }
  
  vkDestroyInstance(instance, null);
}
