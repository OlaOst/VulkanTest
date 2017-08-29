import std.algorithm : all, any, canFind, clamp, countUntil, each, filter, find, map;
import std.array : array;
import std.conv : to;
import std.exception : enforce;
import std.range : enumerate;
import std.stdio : writeln;
import std.string : fromStringz, toStringz;

import derelict.sdl2.sdl;
import erupted;


private void checkVk(VkResult result)
{
  enforce(result == VK_SUCCESS, result.to!string);
}

VkInstance createVulkanInstance(string[] requestedExtensions, string[] requestedValidationLayers)
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
    
    enabledExtensionCount: cast(uint)requestedExtensions.length,
    ppEnabledExtensionNames: requestedExtensions.map!(extension => extension.toStringz).array.ptr,

    enabledLayerCount: cast(uint)requestedValidationLayers.length,
    ppEnabledLayerNames: requestedValidationLayers.map!(layer => layer.toStringz).array.ptr,
  };
  
  VkInstance instance;
  vkCreateInstance(&createInfo, null, &instance).checkVk;

  instance.loadInstanceLevelFunctions();
  instance.loadDeviceLevelFunctions();

  return instance;
}

VkExtensionProperties[] getAvailableExtensions(VkInstance instance)
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
  return requestedValidationLayers.all!(requestedValidationLayerName => availableValidationLayers.any!(availableValidationLayer => requestedValidationLayerName == availableValidationLayer.layerName.ptr.fromStringz));
}

SDL_Window* createSDLWindow()
{
  DerelictSDL2.load(SharedLibVersion(2, 0, 4));
  
  enforce(SDL_Init(SDL_INIT_VIDEO) == 0, "Failed to initialize SDL: " ~ SDL_GetError().to!string);
  
  auto window = SDL_CreateWindow("VulkanTest",
                                 SDL_WINDOWPOS_CENTERED,
                                 SDL_WINDOWPOS_CENTERED,
                                 800,
                                 600,
                                 SDL_WINDOW_SHOWN);

  enforce(window !is null, "Error creating window: " ~ SDL_GetError().to!string);
    
  return window;
}

VkDebugReportCallbackEXT createDebugCallback(VkInstance instance)
{
  PFN_vkDebugReportCallbackEXT debugCallback = (uint flags, 
                                                VkDebugReportObjectTypeEXT objectType,
                                                ulong object,
                                                ulong location,
                                                int messageCode,
                                                const(char)* pLayerPrefix,
                                                const(char)* pMessage,
                                                void* pUserData)
  {
    import core.stdc.stdio;
    printf("Validation layer: %s\n", pMessage);
    return VK_FALSE;
  };
  
  VkDebugReportCallbackCreateInfoEXT createInfo =
  {
    sType: VK_STRUCTURE_TYPE_DEBUG_REPORT_CALLBACK_CREATE_INFO_EXT,
    flags: (VK_DEBUG_REPORT_ERROR_BIT_EXT | VK_DEBUG_REPORT_WARNING_BIT_EXT),
    pfnCallback: debugCallback,
  };
  
  VkDebugReportCallbackEXT callback;
  instance.vkCreateDebugReportCallbackEXT(&createInfo, null, &callback).checkVk;
  
  return callback;
}

VkPhysicalDevice selectPhysicalDevice(VkInstance instance, VkSurfaceKHR surface, string[] requestedDeviceExtensions)
{ 
  uint deviceCount;
  instance.vkEnumeratePhysicalDevices(&deviceCount, null).checkVk;
  
  enforce(deviceCount > 0, "Could not find any physical devices");
  
  VkPhysicalDevice[] devices;
  devices.length = deviceCount;
  instance.vkEnumeratePhysicalDevices(&deviceCount, devices.ptr);

  auto findSuitableDevice = devices.find!(device => device.isDeviceSuitable(surface, requestedDeviceExtensions));
  enforce(findSuitableDevice.length > 0, "Could not find any suitable physical device");
  return findSuitableDevice[0];
}

bool isDeviceSuitable(VkPhysicalDevice physicalDevice, VkSurfaceKHR surface, string[] requestedDeviceExtensions)
{
  VkPhysicalDeviceProperties deviceProperties;
  physicalDevice.vkGetPhysicalDeviceProperties(&deviceProperties);
      
  VkPhysicalDeviceFeatures deviceFeatures;
  physicalDevice.vkGetPhysicalDeviceFeatures(&deviceFeatures);
  
  auto queueFamilyIndices = physicalDevice.getQueueFamilyIndices(surface);
  
  if (requestedDeviceExtensions.length > 0)
  {
    return queueFamilyIndices.isComplete() && 
           physicalDevice.checkDeviceExtensionSupport(requestedDeviceExtensions) && 
           physicalDevice.querySwapchainSupport(surface).isAdequate;
  }
  else
  {
    return queueFamilyIndices.isComplete() && 
           physicalDevice.checkDeviceExtensionSupport(requestedDeviceExtensions);
  }
}

bool checkDeviceExtensionSupport(VkPhysicalDevice physicalDevice, string[] requestedExtensions)
{
  uint extensionCount;
  physicalDevice.vkEnumerateDeviceExtensionProperties(null, &extensionCount, null).checkVk;
  
  VkExtensionProperties[] availableExtensions;
  availableExtensions.length = extensionCount;
  physicalDevice.vkEnumerateDeviceExtensionProperties(null, &extensionCount, availableExtensions.ptr);
    
  return requestedExtensions.all!(requestedExtensionName => availableExtensions.any!(availableExtension => requestedExtensionName == availableExtension.extensionName.ptr.fromStringz));  
}

struct QueueFamilyIndices
{
  int drawingFamilyIndex = -1;
  int presentationFamilyIndex = -1;
  
  bool isComplete()
  {
    return drawingFamilyIndex >= 0 &&
           presentationFamilyIndex >= 0;
  }
}

QueueFamilyIndices getQueueFamilyIndices(VkPhysicalDevice physicalDevice, VkSurfaceKHR surface)
{
  uint queueFamilyCount;
  physicalDevice.vkGetPhysicalDeviceQueueFamilyProperties(&queueFamilyCount, null);
  
  VkQueueFamilyProperties[] queueFamilies;
  queueFamilies.length = queueFamilyCount;
  physicalDevice.vkGetPhysicalDeviceQueueFamilyProperties(&queueFamilyCount, queueFamilies.ptr);
  
  QueueFamilyIndices queueFamilyIndices;
  foreach (uint index, queueFamily; queueFamilies.filter!(queueFamily => queueFamily.queueCount > 0).array)
  {
    if (queueFamily.queueFlags & VK_QUEUE_GRAPHICS_BIT)
      queueFamilyIndices.drawingFamilyIndex = cast(int)index;
      
    VkBool32 presentationSupport = false;
    physicalDevice.vkGetPhysicalDeviceSurfaceSupportKHR(index, surface, &presentationSupport).checkVk;
    
    if (presentationSupport)
      queueFamilyIndices.presentationFamilyIndex = cast(int)index;    
  }
  return queueFamilyIndices;
}

VkDevice createLogicalDevice(VkPhysicalDevice physicalDevice, QueueFamilyIndices queueFamilyIndices, string[] requestedExtensionNames, string[] requestedValidationLayers)
{
  auto queuePriority = 1.0f;
  VkDeviceQueueCreateInfo drawingQueueCreateInfo =
  {
    sType: VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
    queueFamilyIndex: queueFamilyIndices.drawingFamilyIndex,
    queueCount: 1,
    pQueuePriorities: &queuePriority,
  };
  
  auto queueCreateInfos = [drawingQueueCreateInfo];
  
  if (queueFamilyIndices.drawingFamilyIndex != queueFamilyIndices.presentationFamilyIndex)
  {
    VkDeviceQueueCreateInfo presentationQueueCreateInfo =
    {
      sType: VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
      queueFamilyIndex: queueFamilyIndices.presentationFamilyIndex,
      queueCount: 1,
      pQueuePriorities: &queuePriority,
    };
    
    queueCreateInfos ~= presentationQueueCreateInfo;
  }
  
  VkPhysicalDeviceFeatures deviceFeatures =
  {
    // no features wanted yet
  };
  
  VkDeviceCreateInfo logicalDeviceCreateInfo =
  {
    sType: VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
    pQueueCreateInfos: queueCreateInfos.ptr,
    queueCreateInfoCount: cast(uint)queueCreateInfos.length,
    pEnabledFeatures: &deviceFeatures,
    
    enabledExtensionCount: cast(uint)requestedExtensionNames.length,
    ppEnabledExtensionNames: requestedExtensionNames.map!(extension => extension.toStringz).array.ptr,
    
    enabledLayerCount: cast(uint)requestedValidationLayers.length,
    ppEnabledLayerNames: requestedValidationLayers.map!(layer => layer.toStringz).array.ptr,
  };
    
  VkDevice logicalDevice;
  physicalDevice.vkCreateDevice(&logicalDeviceCreateInfo, null, &logicalDevice).checkVk;
  
  logicalDevice.loadDeviceLevelFunctions();
      
  return logicalDevice;
}

VkQueue createDrawingQueue(VkDevice logicalDevice, QueueFamilyIndices queueFamilyIndices)
{
  VkQueue graphicsQueue;
  logicalDevice.vkGetDeviceQueue(queueFamilyIndices.drawingFamilyIndex, 0, &graphicsQueue);
  return graphicsQueue;
}

VkQueue createPresentationQueue(VkDevice logicalDevice, QueueFamilyIndices queueFamilyIndices)
{
  VkQueue presentationQueue;
  logicalDevice.vkGetDeviceQueue(queueFamilyIndices.presentationFamilyIndex, 0, &presentationQueue);
  return presentationQueue;
}

VkSurfaceKHR createSurface(VkInstance instance, SDL_Window* window)
{
  SDL_SysWMinfo wminfo;
  //SDL_VERSION(&wminfo.version_); // compiled version
  SDL_GetVersion(&wminfo.version_); // linked version
  enforce(SDL_GetWindowWMInfo(window, &wminfo) != SDL_FALSE, "Failed to get window info from SDL: " ~ SDL_GetError().to!string);

  VkSurfaceKHR surface;

  version(linux)
  {
    VkXcbSurfaceCreateInfoKHR surfaceCreateInfo =
    {
      sType: VK_STRUCTURE_TYPE_XCB_SURFACE_CREATE_INFO_KHR,
      connection: xcb_connect(null, null),
      window: wminfo.info.x11.window,
    };
    
    instance.vkCreateXcbSurfaceKHR(&surfaceCreateInfo, null, &surface).checkVk;
  }
  else
  {
    assert(0, "This platform is not supported yet");
  }
  
  return surface;
}

struct SwapchainSupportDetails
{
  VkSurfaceCapabilitiesKHR capabilities;
  VkSurfaceFormatKHR[] formats;
  VkPresentModeKHR[] presentModes;
  
  bool isAdequate()
  {
    return formats.length > 0 && presentModes.length > 0;
  }
}

SwapchainSupportDetails querySwapchainSupport(VkPhysicalDevice physicalDevice, VkSurfaceKHR surface)
{
  SwapchainSupportDetails details;
  
  physicalDevice.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(surface, &details.capabilities).checkVk;
  
  uint formatCount;
  physicalDevice.vkGetPhysicalDeviceSurfaceFormatsKHR(surface, &formatCount, null);
  
  details.formats.length = formatCount;
  physicalDevice.vkGetPhysicalDeviceSurfaceFormatsKHR(surface, &formatCount, details.formats.ptr);
  
  uint presentModeCount;
  physicalDevice.vkGetPhysicalDeviceSurfacePresentModesKHR(surface, &presentModeCount, null);
  
  details.presentModes.length = presentModeCount;
  physicalDevice.vkGetPhysicalDeviceSurfacePresentModesKHR(surface, &presentModeCount, details.presentModes.ptr);
  
  return details;
}

VkSurfaceFormatKHR chooseSwapSurfaceFormat(VkSurfaceFormatKHR[] availableFormats)
{
  if (availableFormats.length == 1 && availableFormats[0].format == VK_FORMAT_UNDEFINED)
  {
    return VkSurfaceFormatKHR(VK_FORMAT_B8G8R8A8_UNORM, 
                              VK_COLOR_SPACE_SRGB_NONLINEAR_KHR);
  }
  else
  {
    auto wantedFormatSearch = availableFormats.find!(availableFormat => availableFormat.format == VK_FORMAT_B8G8R8A8_UNORM && availableFormat.colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR);
    
    if (wantedFormatSearch.length == 0)
    {
      return availableFormats[0];
    }
    else
    {
      return wantedFormatSearch[0];
    }
  }
}

VkPresentModeKHR chooseSwapPresentMode(VkPresentModeKHR[] availablePresentModes)
{
  auto desiredPresentModes = [VK_PRESENT_MODE_MAILBOX_KHR,
                              VK_PRESENT_MODE_IMMEDIATE_KHR,
                              VK_PRESENT_MODE_FIFO_KHR];
  
  foreach(desiredPresentMode; desiredPresentModes)
  {
    if (availablePresentModes.canFind(desiredPresentMode))
      return desiredPresentMode;
  }

  scope(failure)
  {
    writeln("Could not find any desired present modes ", desiredPresentModes, " among available present modes ", availablePresentModes);
  }
  
  assert(0);
}

VkExtent2D chooseSwapExtent(VkSurfaceCapabilitiesKHR capabilities)
{
  if (capabilities.currentExtent.width != uint.max)
  {
    return capabilities.currentExtent;
  }
  else
  {
    auto width = 800;
    auto height = 600;
    
    VkExtent2D actualExtent =
    {
      width: width.clamp(capabilities.minImageExtent.width, capabilities.maxImageExtent.width),
      height: height.clamp(capabilities.minImageExtent.height, capabilities.maxImageExtent.height),
    };
    
    return actualExtent;
  }
}

struct Swapchain
{
  VkSwapchainKHR vkSwapchain;
  alias vkSwapchain this;
  
  VkFormat surfaceFormat;
  VkExtent2D extent;
}

Swapchain createSwapchain(VkDevice logicalDevice, VkPhysicalDevice physicalDevice, VkSurfaceKHR surface, QueueFamilyIndices queueFamilyIndices)
{
  auto swapchainSupport = physicalDevice.querySwapchainSupport(surface);
  
  auto surfaceFormat = swapchainSupport.formats.chooseSwapSurfaceFormat();
  auto presentMode = swapchainSupport.presentModes.chooseSwapPresentMode();
  auto extent = swapchainSupport.capabilities.chooseSwapExtent;
  
  uint imageCount = swapchainSupport.capabilities.minImageCount + 1;
  if (swapchainSupport.capabilities.maxImageCount > 0 && imageCount > swapchainSupport.capabilities.maxImageCount)
    imageCount = swapchainSupport.capabilities.maxImageCount;
    
  VkSwapchainCreateInfoKHR swapchainCreateInfo =
  {
    sType: VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
    surface: surface,
    minImageCount: imageCount,
    imageFormat: surfaceFormat.format,
    imageColorSpace: surfaceFormat.colorSpace,
    imageExtent: extent,
    imageArrayLayers: 1,
    imageUsage: VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,

    preTransform: swapchainSupport.capabilities.currentTransform,
    compositeAlpha: VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
    presentMode: presentMode,
    clipped: VK_TRUE,
    oldSwapchain: VK_NULL_HANDLE,
  };
    
  if (queueFamilyIndices.drawingFamilyIndex != queueFamilyIndices.presentationFamilyIndex)
  {
    swapchainCreateInfo.imageSharingMode = VK_SHARING_MODE_CONCURRENT;
    swapchainCreateInfo.queueFamilyIndexCount = 2;
    
    auto indices = [queueFamilyIndices.drawingFamilyIndex, queueFamilyIndices.presentationFamilyIndex];

    swapchainCreateInfo.pQueueFamilyIndices = cast(const(uint)*)indices.ptr;
  }
  else
  {
    swapchainCreateInfo.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE;
    swapchainCreateInfo.queueFamilyIndexCount = 0;
    swapchainCreateInfo.pQueueFamilyIndices = null;
  }
  
  Swapchain swapchain;
  logicalDevice.vkCreateSwapchainKHR(&swapchainCreateInfo, null, &swapchain.vkSwapchain).checkVk;
  
  swapchain.surfaceFormat = surfaceFormat.format;
  swapchain.extent = extent;
    
  return swapchain;
}

VkImage[] getSwapchainImages(VkDevice logicalDevice, VkSwapchainKHR swapchain)
{  
  uint imageCount;
  logicalDevice.vkGetSwapchainImagesKHR(swapchain, &imageCount, null);
  
  VkImage[] swapchainImages;
  swapchainImages.length = imageCount;
  logicalDevice.vkGetSwapchainImagesKHR(swapchain, &imageCount, swapchainImages.ptr);

  return swapchainImages;
}

VkImageView[] createImageViews(VkDevice logicalDevice, Swapchain swapchain)
{
  auto swapchainImages = logicalDevice.getSwapchainImages(swapchain);
  
  VkImageView[] swapchainImageViews;
  swapchainImageViews.length = swapchainImages.length;
    
  foreach (index, swapchainImage; swapchainImages)
  {
    VkImageViewCreateInfo imageViewCreateInfo =
    {
      sType: VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
      image: swapchainImage,
      viewType: VK_IMAGE_VIEW_TYPE_2D,
      format: swapchain.surfaceFormat,
      components: VkComponentMapping(VK_COMPONENT_SWIZZLE_IDENTITY,
                                     VK_COMPONENT_SWIZZLE_IDENTITY,
                                     VK_COMPONENT_SWIZZLE_IDENTITY,
                                     VK_COMPONENT_SWIZZLE_IDENTITY),
      subresourceRange: VkImageSubresourceRange(VK_IMAGE_ASPECT_COLOR_BIT,
                                                0, 1, 0, 1),
    };
    
    logicalDevice.vkCreateImageView(&imageViewCreateInfo, null, &swapchainImageViews[index]).checkVk;
  }
  
  return swapchainImageViews;
}

VkPipeline createGraphicsPipeline(VkDevice logicalDevice, Swapchain swapchain, VkRenderPass renderPass, out VkPipelineLayout pipelineLayout)
{
  import std.file : read;
  
  auto vertShaderCode = "shaders/vert.spv".read;
  auto fragShaderCode = "shaders/frag.spv".read;
    
  auto vertShaderModule = logicalDevice.createShaderModule(vertShaderCode);
  scope(exit) logicalDevice.vkDestroyShaderModule(vertShaderModule, null);
  
  auto fragShaderModule = logicalDevice.createShaderModule(fragShaderCode);
  scope(exit) logicalDevice.vkDestroyShaderModule(fragShaderModule, null);
  
  VkPipelineShaderStageCreateInfo vertShaderStageCreateInfo =
  {
    sType: VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
    stage: VK_SHADER_STAGE_VERTEX_BIT,
    _module: vertShaderModule,
    pName: "main",
  };
  
  VkPipelineShaderStageCreateInfo fragShaderStageCreateInfo =
  {
    sType: VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
    stage: VK_SHADER_STAGE_FRAGMENT_BIT,
    _module: fragShaderModule,
    pName: "main",
  };
  
  auto shaderStages = [vertShaderStageCreateInfo, fragShaderStageCreateInfo];
  
  VkPipelineVertexInputStateCreateInfo vertexInputStateCreateInfo =
  {
    sType: VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
    vertexBindingDescriptionCount: 0,
    pVertexBindingDescriptions: null,
    vertexAttributeDescriptionCount: 0,
    pVertexAttributeDescriptions: null,
  };
  
  VkPipelineInputAssemblyStateCreateInfo inputAssemblyStateCreateInfo =
  {
    sType: VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
    topology: VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
    primitiveRestartEnable: VK_FALSE,
  };
  
  VkViewport viewport =
  {
    x: 0.0f,
    y: 0.0f,
    width: cast(float)swapchain.extent.width,
    height: cast(float)swapchain.extent.height,
    minDepth: 0.0f,
    maxDepth: 1.0f,
  };
  
  VkRect2D scissor =
  {
    offset: VkOffset2D(0, 0),
    extent: swapchain.extent,
  };
  
  VkPipelineViewportStateCreateInfo viewportStateCreateInfo =
  {
    sType: VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
    viewportCount: 1,
    pViewports: &viewport,
    scissorCount: 1,
    pScissors: &scissor,
  };
  
  VkPipelineRasterizationStateCreateInfo rasterizationStateCreateInfo =
  {
    sType: VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
    depthClampEnable: VK_FALSE,
    rasterizerDiscardEnable: VK_FALSE,
    polygonMode: VK_POLYGON_MODE_FILL,
    lineWidth: 1.0f,
    cullMode: VK_CULL_MODE_BACK_BIT,
    frontFace: VK_FRONT_FACE_CLOCKWISE,
    depthBiasEnable: VK_FALSE,
    depthBiasConstantFactor: 0.0f,
    depthBiasClamp: 0.0f,
    depthBiasSlopeFactor: 0.0f,
  };
  
  VkPipelineMultisampleStateCreateInfo multisampleStateCreateInfo =
  {
    sType: VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
    sampleShadingEnable: VK_FALSE,
    rasterizationSamples: VK_SAMPLE_COUNT_1_BIT,
    minSampleShading: 1.0f,
    pSampleMask: null,
    alphaToCoverageEnable: VK_FALSE,
    alphaToOneEnable: VK_FALSE,
  };
  
  VkPipelineColorBlendAttachmentState colorBlendAttachment =
  {
    colorWriteMask: VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT | VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT,
    blendEnable: VK_FALSE,
    srcColorBlendFactor: VK_BLEND_FACTOR_ONE,
    dstColorBlendFactor: VK_BLEND_FACTOR_ZERO,
    colorBlendOp: VK_BLEND_OP_ADD,
    srcAlphaBlendFactor: VK_BLEND_FACTOR_ONE,
    dstAlphaBlendFactor: VK_BLEND_FACTOR_ZERO,
    alphaBlendOp: VK_BLEND_OP_ADD,
  };
  
  VkPipelineColorBlendStateCreateInfo colorBlendStateCreateInfo =
  {
    sType: VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
    logicOpEnable: VK_FALSE,
    logicOp: VK_LOGIC_OP_COPY,
    attachmentCount: 1,
    pAttachments: &colorBlendAttachment,
    blendConstants: [0.0f, 0.0f, 0.0f, 0.0f],
  };
  
  auto dynamicStates = [VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_LINE_WIDTH];
  
  VkPipelineDynamicStateCreateInfo dynamicStateCreateInfo =
  {
    sType: VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
    dynamicStateCount: 2,
    pDynamicStates: dynamicStates.ptr,
  };
  
  VkPipelineLayoutCreateInfo pipelineLayoutCreateInfo =
  {
    sType: VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
    setLayoutCount: 0,
    pSetLayouts: null,
    pushConstantRangeCount: 0,
    pPushConstantRanges: null,
  };
  
  logicalDevice.vkCreatePipelineLayout(&pipelineLayoutCreateInfo, null, &pipelineLayout).checkVk;
  
  VkGraphicsPipelineCreateInfo pipelineCreateInfo =
  {
    sType: VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
    stageCount: 2,
    pStages: shaderStages.ptr,
    pVertexInputState: &vertexInputStateCreateInfo,
    pInputAssemblyState: &inputAssemblyStateCreateInfo,
    pViewportState: &viewportStateCreateInfo,
    pRasterizationState: &rasterizationStateCreateInfo,
    pMultisampleState: &multisampleStateCreateInfo,
    pDepthStencilState: null,
    pColorBlendState: &colorBlendStateCreateInfo,
    pDynamicState: null,
    layout: pipelineLayout,
    renderPass: renderPass,
    subpass: 0,
    basePipelineHandle: VK_NULL_HANDLE,
    basePipelineIndex: -1,
  };
  
  VkPipeline graphicsPipeline;
  logicalDevice.vkCreateGraphicsPipelines(VK_NULL_HANDLE, 1, &pipelineCreateInfo, null, &graphicsPipeline).checkVk;
  return graphicsPipeline;
}

VkShaderModule createShaderModule(VkDevice logicalDevice, void[] shaderCode)
{
  VkShaderModuleCreateInfo shaderModuleCreateInfo =
  {
    sType: VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
    codeSize: shaderCode.length,
    pCode: cast(uint*)(shaderCode.ptr),
  };
  
  VkShaderModule shaderModule;
  logicalDevice.vkCreateShaderModule(&shaderModuleCreateInfo, null, &shaderModule).checkVk;
  
  return shaderModule;
}

VkRenderPass createRenderPass(VkDevice logicalDevice, Swapchain swapchain)
{
  VkAttachmentDescription colorAttachment =
  {
    format: swapchain.surfaceFormat,
    samples: VK_SAMPLE_COUNT_1_BIT,
    loadOp: VK_ATTACHMENT_LOAD_OP_CLEAR,
    storeOp: VK_ATTACHMENT_STORE_OP_STORE,
    stencilLoadOp: VK_ATTACHMENT_LOAD_OP_DONT_CARE,
    stencilStoreOp: VK_ATTACHMENT_STORE_OP_DONT_CARE,
    initialLayout: VK_IMAGE_LAYOUT_UNDEFINED,
    finalLayout: VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
  };
  
  VkAttachmentReference colorAttachmentReference =
  {
    attachment: 0,
    layout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
  };
  
  VkSubpassDescription subpassDescription =
  {
    pipelineBindPoint: VK_PIPELINE_BIND_POINT_GRAPHICS,
    colorAttachmentCount: 1,
    pColorAttachments: &colorAttachmentReference,
  };
  
  VkSubpassDependency subpassDependency =
  {
    srcSubpass: VK_SUBPASS_EXTERNAL,
    dstSubpass: 0,
    
    srcStageMask: VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
    srcAccessMask: 0,
    
    dstStageMask: VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
    dstAccessMask: VK_ACCESS_COLOR_ATTACHMENT_READ_BIT | VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
  };
  
  VkRenderPassCreateInfo renderPassCreateInfo =
  {
    sType: VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,

    attachmentCount: 1,
    pAttachments: &colorAttachment,

    subpassCount: 1,
    pSubpasses: &subpassDescription,
    
    dependencyCount: 1,
    pDependencies: &subpassDependency,
  };
  
  VkRenderPass renderPass;
  logicalDevice.vkCreateRenderPass(&renderPassCreateInfo, null, &renderPass).checkVk;
  return renderPass;
}

VkFramebuffer[] createFramebuffers(VkDevice logicalDevice, Swapchain swapchain, VkRenderPass renderPass, VkImageView[] imageViews)
{
  VkFramebuffer[] framebuffers;
  framebuffers.length = imageViews.length;
  
  foreach (index, imageView; imageViews)
  {
    auto attachments = [imageView];
    
    VkFramebufferCreateInfo framebufferCreateInfo =
    {
      sType: VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
      renderPass: renderPass,
      attachmentCount: cast(uint)attachments.length,
      pAttachments: attachments.ptr,
      width: swapchain.extent.width,
      height: swapchain.extent.height,
      layers: 1,
    };
    
    logicalDevice.vkCreateFramebuffer(&framebufferCreateInfo, null, &framebuffers[index]).checkVk;
  }
  
  return framebuffers;
}

VkCommandPool createCommandPool(VkDevice logicalDevice, QueueFamilyIndices queueFamilyIndices)
{  
  VkCommandPoolCreateInfo commandPoolCreateInfo =
  {
    sType: VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
    queueFamilyIndex: queueFamilyIndices.drawingFamilyIndex,
    flags: 0,
  };
 
  VkCommandPool commandPool; 
  logicalDevice.vkCreateCommandPool(&commandPoolCreateInfo, null, &commandPool).checkVk;
  
  return commandPool;
}

VkCommandBuffer[] createCommandBuffers(VkDevice logicalDevice, VkFramebuffer[] framebuffers, VkCommandPool commandPool)
{  
  VkCommandBufferAllocateInfo commandBufferAllocateInfo =
  {
    sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
    commandPool: commandPool,
    level: VK_COMMAND_BUFFER_LEVEL_PRIMARY,
    commandBufferCount: cast(uint)framebuffers.length,
  };
 
  VkCommandBuffer[] commandBuffers;
  commandBuffers.length = framebuffers.length;
   
  logicalDevice.vkAllocateCommandBuffers(&commandBufferAllocateInfo, commandBuffers.ptr).checkVk;
  
  return commandBuffers;
}

void recordCommandBuffers(VkCommandBuffer[] commandBuffers, VkRenderPass renderPass, VkFramebuffer[] framebuffers, Swapchain swapchain, VkPipeline graphicsPipeline)
{
  foreach (index, commandBuffer; commandBuffers)
  {
    VkCommandBufferBeginInfo commandBufferBeginInfo =
    {
      sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
      flags: VK_COMMAND_BUFFER_USAGE_SIMULTANEOUS_USE_BIT,
      pInheritanceInfo: null,
    };
    
    commandBuffer.vkBeginCommandBuffer(&commandBufferBeginInfo);
    
    auto clearValue = VkClearValue(VkClearColorValue([0.0f, 0.0f, 0.0f, 1.0f]));    
    VkRenderPassBeginInfo renderPassBeginInfo =
    {
      sType: VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
      renderPass: renderPass,
      framebuffer: framebuffers[index],
      renderArea: VkRect2D(VkOffset2D(0, 0), swapchain.extent),
      clearValueCount: 1,
      pClearValues: &clearValue,
    };
    
    commandBuffer.vkCmdBeginRenderPass(&renderPassBeginInfo, VK_SUBPASS_CONTENTS_INLINE);
    
    commandBuffer.vkCmdBindPipeline(VK_PIPELINE_BIND_POINT_GRAPHICS, graphicsPipeline);

    commandBuffer.vkCmdDraw(3, 1, 0, 0);
    
    commandBuffer.vkCmdEndRenderPass();
    
    commandBuffer.vkEndCommandBuffer().checkVk;
  }
}

void mainLoop(VkDevice logicalDevice, Swapchain swapchain, VkSemaphore imageAvailableSemaphore, VkSemaphore renderFinishedSemaphore, VkCommandBuffer[] commandBuffers, VkQueue drawingQueue, VkQueue presentationQueue)
{
  bool running = true;
  while (running)
  {
    SDL_Event event;
    SDL_PollEvent(&event);
    
    if (event.type == SDL_QUIT)
      running = false;
    if (event.type == SDL_KEYUP && event.key.keysym.sym == SDLK_ESCAPE)
      running = false;
      
    logicalDevice.drawFrame(swapchain, imageAvailableSemaphore, renderFinishedSemaphore, commandBuffers, drawingQueue, presentationQueue);
  }
}

void drawFrame(VkDevice logicalDevice, Swapchain swapchain, VkSemaphore imageAvailableSemaphore, VkSemaphore renderFinishedSemaphore, VkCommandBuffer[] commandBuffers, VkQueue drawingQueue, VkQueue presentationQueue)
{
  uint imageIndex;
  logicalDevice.vkAcquireNextImageKHR(swapchain, ulong.max, imageAvailableSemaphore, VK_NULL_HANDLE, &imageIndex);
  
  VkSubmitInfo submitInfo =
  {
    sType: VK_STRUCTURE_TYPE_SUBMIT_INFO,

    waitSemaphoreCount: 1,
    pWaitSemaphores: [imageAvailableSemaphore].ptr,
    pWaitDstStageMask: [VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT],
    
    commandBufferCount: 1,
    pCommandBuffers: &commandBuffers[imageIndex],
    
    signalSemaphoreCount: 1,
    pSignalSemaphores: [renderFinishedSemaphore],
  };
  
  drawingQueue.vkQueueSubmit(1, &submitInfo, VK_NULL_HANDLE).checkVk;
  
  VkPresentInfoKHR presentInfo =
  {
    sType: VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
    
    waitSemaphoreCount: 1,
    pWaitSemaphores: [renderFinishedSemaphore],
    
    swapchainCount: 1,
    pSwapchains: [swapchain],
    pImageIndices: &imageIndex,
    
    pResults: null,
  };
  
  presentationQueue.vkQueuePresentKHR(&presentInfo);
}

VkSemaphore createSemaphore(VkDevice logicalDevice)
{
  VkSemaphoreCreateInfo semaphoreCreateInfo = 
  {
    sType: VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
  };
  
  VkSemaphore semaphore;
  logicalDevice.vkCreateSemaphore(&semaphoreCreateInfo, null, &semaphore).checkVk;
  return semaphore;
}

void main()
{
  string[] requestedExtensions = ["VK_KHR_surface"];
  version(linux) requestedExtensions ~= ["VK_KHR_xcb_surface"];
  debug requestedExtensions ~= ["VK_EXT_debug_report"];

  string[] requestedValidationLayers;
  debug requestedValidationLayers ~= ["VK_LAYER_LUNARG_standard_validation"];
    
  auto instance = createVulkanInstance(requestedExtensions, requestedValidationLayers);
  scope(exit) vkDestroyInstance(instance, null);

  auto debugCallback = instance.createDebugCallback();
  scope(exit) instance.vkDestroyDebugReportCallbackEXT(debugCallback, null);

  auto window = createSDLWindow();

  auto surface = instance.createSurface(window);
  scope(exit) instance.vkDestroySurfaceKHR(surface, null);

  auto requestedDeviceExtensions = ["VK_KHR_swapchain"];

  auto physicalDevice = instance.selectPhysicalDevice(surface, requestedDeviceExtensions);

  auto queueFamilyIndices = physicalDevice.getQueueFamilyIndices(surface);
    
  auto logicalDevice = physicalDevice.createLogicalDevice(queueFamilyIndices, requestedDeviceExtensions, requestedValidationLayers);
  scope(exit) logicalDevice.vkDestroyDevice(null);

  auto drawingQueue = logicalDevice.createDrawingQueue(queueFamilyIndices);
  auto presentationQueue = logicalDevice.createPresentationQueue(queueFamilyIndices);
  
  auto swapchain = logicalDevice.createSwapchain(physicalDevice, surface, queueFamilyIndices);
  scope(exit) logicalDevice.vkDestroySwapchainKHR(swapchain, null);
  
  auto imageViews = logicalDevice.createImageViews(swapchain);
  scope(exit) imageViews.each!(imageView => logicalDevice.vkDestroyImageView(imageView, null));

  auto renderPass = logicalDevice.createRenderPass(swapchain);
  scope(exit) logicalDevice.vkDestroyRenderPass(renderPass, null);

  VkPipelineLayout pipelineLayout;  
  auto graphicsPipeline = logicalDevice.createGraphicsPipeline(swapchain, renderPass, pipelineLayout);
  scope(exit) logicalDevice.vkDestroyPipeline(graphicsPipeline, null);
  scope(exit) logicalDevice.vkDestroyPipelineLayout(pipelineLayout, null);
  
  auto framebuffers = logicalDevice.createFramebuffers(swapchain, renderPass, imageViews);
  scope(exit) framebuffers.each!(framebuffer => logicalDevice.vkDestroyFramebuffer(framebuffer, null));

  auto commandPool = logicalDevice.createCommandPool(queueFamilyIndices);
  scope(exit) logicalDevice.vkDestroyCommandPool(commandPool, null);

  auto commandBuffers = createCommandBuffers(logicalDevice, framebuffers, commandPool);
  commandBuffers.recordCommandBuffers(renderPass, framebuffers, swapchain, graphicsPipeline);

  auto imageAvailableSemaphore = logicalDevice.createSemaphore();
  scope(exit) logicalDevice.vkDestroySemaphore(imageAvailableSemaphore, null);

  auto renderFinishedSemaphore = logicalDevice.createSemaphore();
  scope(exit) logicalDevice.vkDestroySemaphore(renderFinishedSemaphore, null);

  logicalDevice.mainLoop(swapchain, imageAvailableSemaphore, renderFinishedSemaphore, commandBuffers, drawingQueue, presentationQueue);
  
  debug
  {    
    enforce(instance.checkValidationLayerSupport(requestedValidationLayers),
            "Could not find requested validation layers " ~ requestedValidationLayers.to!string ~ " in available layers " ~ instance.getAvailableLayers().map!(layer => layer.layerName.ptr.fromStringz).to!string);
  }  
}
