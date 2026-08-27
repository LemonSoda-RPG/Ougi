# Ougi
Default plugin repository for LANraragi.  
If you want to fetch metadata from a random txt/json/yaml format, you can probably find a plugin for it here.  

This repository is parametered by default on all LANraragi installs, so if you want to install plugins from here, you can do so directly from your LRR instance by following the [Documentation.]()  

### Contributing a new plugin 

Fork this repository and create your plugin in a new directory under `arifacts`.  
Make sure to mention the type of your plugin in the directory, e.g `artifacts/metadata-example-info-txt/0.0.1/Plugin.pm`.

You can test your plugin by then adding your Git fork as an [additional repository]() on your LANraragi instance.  
Once you're done with development, just open a PR to get it reviewed/added!  

If your plugin has tests, you can put the matching .t files in tests/[plugin-name].  
For example, `tests/metadata-example-info-txt/0.0.1/Plugin.t`.  
Any additional files (mocks, sample files, etc) should be in the same directory as the test. 

### Contributing an update to an existing plugin  

Just make a PR directly modifying the existing plugin.  
Make sure to bump the version, but **do not** create a new subfolder/move the plugin. This allows us to review the actual plugin diff more easily.  
Once the PR is approved by a maintainer, a CI workflow will automatically complete your PR by moving the plugin to a new versioned subdirectory and regenerate the registry.json.  