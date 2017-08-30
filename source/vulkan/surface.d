module vulkan.surface;

import std.exception : enforce;

import derelict.sdl2.sdl;
import erupted;

import vulkan.check;
import vulkan.instance;


struct Surface
{
  VkSurfaceKHR surface;
  alias surface this;
    
  VkInstance instance;
  
  this(VkInstance instance, SDL_Window* window)
  {
    this.instance = instance;
    
    SDL_SysWMinfo wminfo;
    //SDL_VERSION(&wminfo.version_) // compiled version
    SDL_GetVersion(&wminfo.version_); // linked version
    enforce(SDL_GetWindowWMInfo(window, &wminfo) != SDL_FALSE, 
            "Failed to get window info from SDL: " ~ SDL_GetError().to!string);
            
    version(linux)
    {
      VkXcbSurfaceCreateInfoKHR surfaceCreateInfo =
      {
        connection: xcb_connect(null, null),
        window: wminfo.info.x11.window,
      };
      
      instance.vkCreateXcbSurfaceKHR(&surfaceCreateInfo, null, &surface).checkVk;
    }
    else
    {
      assert(0, "This platform is not supported yet");
    }
  }
  
  ~this()
  {
    instance.vkDestroySurfaceKHR(surface, null);
  }
}
