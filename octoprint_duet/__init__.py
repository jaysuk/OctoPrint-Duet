# coding=utf-8
from __future__ import absolute_import

import octoprint.plugin
import octoprint.settings

from octoprint.server import app
from flask import Blueprint, render_template, abort
from jinja2 import TemplateNotFound

duetwebcontrol = Blueprint("duet", __name__, template_folder="www", static_url_path='', static_folder="www")

@duetwebcontrol.route('/')
@duetwebcontrol.route('/reprap')
def reprap():
	try:
		return render_template('reprap.htm')
	except TemplateNotFound:
		abort(404)

@duetwebcontrol.route('/js/comm.js')
def js_comm():
	r = duetwebcontrol.send_static_file('js/comm.js')
	
	apiUrl = __plugin_implementation__._settings.get(["apiUrl"])
	if apiUrl.startswith('/'):
		r.data = r.data.replace("ajaxPrefix = \"\"", "ajaxPrefix = window.location.origin + \"" + apiUrl + "\"")
	else:
		r.data = r.data.replace("ajaxPrefix = \"\"", "ajaxPrefix = \"" + apiUrl + "\"")
	return r

class DuetPlugin(octoprint.plugin.SettingsPlugin,
                octoprint.plugin.AssetPlugin,
                octoprint.plugin.TemplatePlugin,
                octoprint.plugin.StartupPlugin):

	def __init__(self):
		pass

	##~~ SettingsPlugin mixin

	def get_settings_defaults(self):
		return dict(
			apiUrl = "/duet/",
			password = "reprap"    
		)

	##~~ AssetPlugin mixin

	def get_assets(self):
		# Define your plugin's asset files to automatically include in the
		# core UI here.
		return dict(
			js=["js/duet.js"],
			css=["css/duet.css"],
			less=["less/duet.less"]
		)

	#~~ StartupPlugin

	def on_startup(self, *args, **kwargs):
		app.register_blueprint(duetwebcontrol, url_prefix="/duetwebcontrol")

	##~~ Softwareupdate hook

	def get_update_information(self):
		# Define the configuration for your plugin to use with the Software Update
		# Plugin here. See https://github.com/foosel/OctoPrint/wiki/Plugin:-Software-Update
		# for details.
		return dict(
			duet=dict(
				displayName="Duet",
				displayVersion=self._plugin_version,

				# version check: github repository
				type="github_release",
				user="trilab3d",
				repo="OctoPrint-Duet",
				current=self._plugin_version,

				# update method: pip
				pip="https://github.com/trilab3d/OctoPrint-Duet/archive/{target_version}.zip"
			)
		)


# If you want your plugin to be registered within OctoPrint under a different name than what you defined in setup.py
# ("OctoPrint-PluginSkeleton"), you may define that here. Same goes for the other metadata derived from setup.py that
# can be overwritten via __plugin_xyz__ control properties. See the documentation for that.
__plugin_name__ = "Duet"

def __plugin_load__():
	global __plugin_implementation__
	__plugin_implementation__ = DuetPlugin()

	global __plugin_hooks__
	__plugin_hooks__ = {
		"octoprint.plugin.softwareupdate.check_config": __plugin_implementation__.get_update_information
	}

