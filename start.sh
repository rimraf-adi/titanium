#!/bin/bash
sudo apt update
sudo apt upgrade
sudo apt-get install python


curl -LsSf https://astral.sh/uv/install.sh | sh
read project_name
uv init $project_name

