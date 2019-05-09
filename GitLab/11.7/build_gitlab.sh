#!/bin/bash
# © Copyright IBM Corporation 2019.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/GitLab/11.7/build_gitlab.sh
# Execute build script: bash build_gitlab.sh    (provide -h for help)
#

set -e -o pipefail

PACKAGE_NAME="GitLab"
PACKAGE_VERSION="11.7"
CURDIR="$(pwd)"
REPO_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/GitLab/11.7/patch/"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
TEST_USER="$(whoami)"
FORCE="false"
NC="$(nproc)"
trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
	mkdir -p "$CURDIR/logs/"
fi

#
if [ -f "/etc/os-release" ]; then
	source "/etc/os-release"
fi

function prepare() {

	if [[ "${TEST_USER}" != "root" ]]; then
		printf -- 'Cannot run gitlab as non-root . Please switch to superuser \n' |& tee -a "$LOG_FILE"
		exit 1
	fi

	if [[ "$FORCE" == "true" ]]; then
		printf -- 'Force attribute provided hence continuing with install without confirmation message\n' |& tee -a "$LOG_FILE"
	else
		if [[ "${ID}" == "ubuntu" ]]; then
			printf -- '\nFollowing packages are needed before going ahead\n' |& tee -a "$LOG_FILE"
			printf -- 'git version: 2.18.0 \n' |& tee -a "$LOG_FILE"
			printf -- 'ruby version: 2.5.3  \n' |& tee -a "$LOG_FILE"
			printf -- 'go version: 1.10.3  \n' |& tee -a "$LOG_FILE"
			printf -- 'node version: 8.11.4  \n' |& tee -a "$LOG_FILE"
			printf -- 'yarn version: 1.13.0 \n' |& tee -a "$LOG_FILE"

			printf -- '\nBuild might take some time, please have patience . \n' |& tee -a "$LOG_FILE"
			while true; do
				read -r -p "Do you want to continue (y/n) ? :  " yn
				case $yn in
				[Yy]*)
					break
					;;
				[Nn]*) exit ;;
				*) echo "Please provide Correct input to proceed." |& tee -a "$LOG_FILE" ;;
				esac
			done
		fi
	fi
}

function cleanup() {

	#Remove tar files
	rm -rf "${CURDIR}/go1.10.3.linux-s390x.tar.gz"
	rm -rf "${CURDIR}/node-v8.11.4-linux-s390x.tar.xz"
	rm -rf "${CURDIR}/yarn-v1.13.0.tar.gz"
	rm -rf "${CURDIR}/ruby-2.5.3.tar.gz"
	rm -rf "${CURDIR}/git-2.18.0.tar.gz"
	
	#Remove downloaded patches
	rm -rf "${CURDIR}/Gemfile_gitaly_uncomment.diff"
	rm -rf "${CURDIR}/gitaly-proto/release.diff"
	rm -rf "${CURDIR}/gitaly-proto/Makefile_gitlay_proto.diff"
	rm -rf "${CURDIR}/grpc/tools/openssl/use_openssl.sh.diff"
	rm -rf "${CURDIR}/grpc/tools/openssl/Makefile.diff"
	rm -rf "${CURDIR}/grpc/extconf.rb.diff"
	rm -rf "${CURDIR}/grpc/src/ruby/grpc.gemspec.diff"
	rm -rf "${CURDIR}/Makefile_gitaly.diff"
	rm -rf "${CURDIR}/protobuf/upb.c.diff"
	rm -rf "${CURDIR}/protobuf/test_ruby_package.proto.diff"
	rm -rf "${CURDIR}/protobuf/Rakefile.diff"
	rm -rf "${CURDIR}/protobuf/upb.h.diff"
	rm -rf "${CURDIR}/makegen.go.diff"
	rm -rf "/home/git/gitlab/Gemfile.lock.diff"
	rm -rf "/home/git/gitlab/Gemfile_uncomment.diff"
	rm -rf "/home/git/gitlab/gitlab.yml.diff"
	rm -rf "/home/git/gitlab/Gemfile_gitaly_comment.diff"
	rm -rf "/home/git/gitlab/setup.rake.diff"
	rm -rf "/home/git/gitlab/gitaly.rake.diff"
	rm -rf "/home/git/gitlab/Gemfile_comment.diff"

	printf -- '\nCleaned up the artifacts\n' >>"$LOG_FILE"
}

#Installing dependencies
function dependencyInstall() {
	printf -- 'Building dependencies\n'

	# Install git
	printf -- 'Installing git \n'
	cd "${CURDIR}"
	wget https://www.kernel.org/pub/software/scm/git/git-2.18.0.tar.gz
	tar -xzf git-2.18.0.tar.gz
	cd git-2.18.0/
	./configure
	make prefix=/usr/local all
	make prefix=/usr/local install
	printf -- 'Installed git successfully\n'

	# Install Ruby
	printf -- 'Installing ruby \n'
	cd "${CURDIR}"
	curl --remote-name --progress https://cache.ruby-lang.org/pub/ruby/2.5/ruby-2.5.3.tar.gz
	echo 'f919a9fbcdb7abecd887157b49833663c5c15fda  ruby-2.5.3.tar.gz' | shasum -c - && tar xzf ruby-2.5.3.tar.gz
	cd ruby-2.5.3
	./configure --disable-install-rdoc
	make
	make install
	printf -- 'Installed ruby successfully\n'

	#Install the Bundler Gem:
	gem install bundler --no-document --version '< 2'

	# Remove former Go installation folder
	rm -rf /usr/local/go

	#Install Go
	printf -- 'Installing go \n'
	cd "${CURDIR}"
	curl --remote-name --progress https://dl.google.com/go/go1.10.3.linux-s390x.tar.gz
	echo '34385f64651f82fbc11dc43bdc410c2abda237bdef87f3a430d35a508ec3ce0d  go1.10.3.linux-s390x.tar.gz' | shasum -a256 -c - && sudo tar -C /usr/local -xzf go1.10.3.linux-s390x.tar.gz
	ln -sf /usr/local/go/bin/{go,godoc,gofmt} /usr/local/bin/
	go version
	printf -- 'Installed go successfully \n'

	# Install Node
	printf -- 'Installing node \n'
	cd "${CURDIR}"
	wget https://nodejs.org/dist/v8.11.4/node-v8.11.4-linux-s390x.tar.xz
	tar -C /usr/local -xf node-v8.11.4-linux-s390x.tar.xz
	export PATH=/usr/local/node-v8.11.4-linux-s390x/bin:$PATH
	node --version
	printf -- 'Installed node successfully \n'

	#Install Yarn
	printf -- 'Installing yarn \n'
	cd "${CURDIR}"
	wget https://github.com/yarnpkg/yarn/releases/download/v1.13.0/yarn-v1.13.0.tar.gz
	tar -C /usr/local -xf yarn-v1.13.0.tar.gz
	export PATH=/usr/local/yarn-v1.13.0/bin:$PATH
	yarn --version
	printf -- 'Installed yarn successfully \n'

}


function configureAndInstall() {
	printf -- '\nConfiguration and Installation started \n'
	#Installing dependencies
	cd "${CURDIR}" 

	printf -- '\nConfiguring the database\n'
	#Create a `git` user for GitLab:
	adduser --disabled-login --gecos 'GitLab' git

	#Start Postgres server
	cd /home/git
	mkdir -p /usr/local/pgsql/data
	chown postgres:postgres /usr/local/pgsql/data
	sudo su -m postgres -c '/usr/lib/postgresql/10/bin/initdb -D /usr/local/pgsql/data --encoding=UTF8'
	sudo su -m postgres -c '/usr/lib/postgresql/10/bin/pg_ctl -D /usr/local/pgsql/data -l /tmp/logfile start'

	#Check if postgres is running
	ps -aef | grep postgres
	#Create a database user for GitLab
	sudo -u postgres psql -d template1 -c "CREATE USER git CREATEDB;"
	#Create the `pg_trgm` extension (required for GitLab 8.6+)
	sudo -u postgres psql -d template1 -c "CREATE EXTENSION IF NOT EXISTS pg_trgm;"
	#Create the GitLab production database and grant all privileges on database
	sudo -u postgres psql -d template1 -c "CREATE DATABASE gitlabhq_production OWNER git;"

	#Try connecting to the new database with the new user
	#Check if the `pg_trgm` extension is enabled
	sudo -u git -H  psql -d gitlabhq_production -c "SELECT true AS enabled FROM pg_available_extensions WHERE name = 'pg_trgm' AND installed_version IS NOT NULL;"
	
	# Configure redis to use sockets
	cp /etc/redis/redis.conf /etc/redis/redis.conf.orig

	# Disable Redis listening on TCP by setting 'port' to 0
	sed 's/^port .*/port 0/' /etc/redis/redis.conf.orig | sudo tee /etc/redis/redis.conf

	# Enable Redis socket for default Debian / Ubuntu path
	echo 'unixsocket /var/run/redis/redis.sock' | sudo tee -a /etc/redis/redis.conf

	# Grant permission to the socket to all members of the redis group
	echo 'unixsocketperm 770' | sudo tee -a /etc/redis/redis.conf

	# Create the directory which contains the socket
	mkdir /var/run/redis
	chown redis:redis /var/run/redis
	chmod 755 /var/run/redis

	# Persist the directory which contains the socket, if applicable
	echo 'd  /var/run/redis  0755  redis  redis  10d  -' | sudo tee -a /etc/tmpfiles.d/redis.conf

	# Activate the changes to redis.conf
	service redis-server restart

	# Add git to the redis group
	usermod -aG redis git

	
	# Fetch google-protobuf source
	printf -- 'Building google-protobuf gem \n'
	cd "${CURDIR}" 
	git clone -b v3.6.1 https://github.com/protocolbuffers/protobuf.git
	cd protobuf/

	curl -o upb.c.diff $REPO_URL/upb.c.diff
	patch $CURDIR/protobuf/ruby/ext/google/protobuf_c/upb.c upb.c.diff

	curl -o upb.h.diff $REPO_URL/upb.h.diff
	patch $CURDIR/protobuf/ruby/ext/google/protobuf_c/upb.h upb.h.diff

	curl -o Rakefile.diff $REPO_URL/Rakefile.diff
	patch $CURDIR/protobuf/ruby/Rakefile Rakefile.diff

	curl -o test_ruby_package.proto.diff $REPO_URL/test_ruby_package.proto.diff
	patch $CURDIR/protobuf/ruby/tests/test_ruby_package.proto test_ruby_package.proto.diff

	#Build google-protobuf gem
	cd ruby/
	cp /usr/bin/protoc ./src/
	bundle
	rake
	rake clobber_package gem
	cp pkg/google-protobuf-3.6.1.gem "$CURDIR/"
	printf -- 'Built google-protobuf gem successfully\n'

	#Fetch grpc source
	printf -- 'Building grpc gem \n'
	cd $CURDIR
	git clone -b v1.15.0 https://github.com/grpc/grpc.git
	cd grpc/tools/openssl
	curl -o use_openssl.sh.diff $REPO_URL/use_openssl.sh.diff
	patch $CURDIR/grpc/tools/openssl/use_openssl.sh use_openssl.sh.diff

	#Run the script
	chmod +x use_openssl.sh
	./use_openssl.sh

	#Fetch Makefile
	curl -o Makefile.diff $REPO_URL/Makefile_grpc.diff
	sed -i "s|CURDIR|${CURDIR}|g" Makefile.diff
	patch $CURDIR/grpc/Makefile Makefile.diff

	# Build GRPC source
	cd "$CURDIR/grpc/src/ruby/"
	git submodule update --init
	cd "$CURDIR/grpc/"
	make


	curl -o extconf.rb.diff $REPO_URL/extconf.rb.diff
	patch $CURDIR/grpc/src/ruby/ext/grpc/extconf.rb extconf.rb.diff

	#Create local gem repository
	cd $CURDIR/grpc
	bundle install
	mkdir -p $CURDIR/GEMREPO/repo/gems
	cp /usr/local/lib/ruby/gems/2.5.0/cache/*.gem $CURDIR/GEMREPO/repo/gems
	cp $CURDIR/google-protobuf-3.6.1.gem $CURDIR/GEMREPO/repo/gems/google-protobuf-3.6.1.gem
	cd $CURDIR/GEMREPO/repo/
	gem install builder
	gem generate_index
	cd $CURDIR/grpc/src/ruby
	bundle clean --force
	set +e
	yes | gem uninstall --all --force
	gem install bundler --no-document --version '< 2'
	set -e
	curl -o grpc.gemspec.diff $REPO_URL/grpc.gemspec.diff
	patch $CURDIR/grpc/grpc.gemspec grpc.gemspec.diff

	cd $CURDIR/grpc/src/ruby
	sed -i "s|https://rubygems.org|file:${CURDIR}/GEMREPO/repo|" $CURDIR/grpc/Gemfile
	bundle install
	rake
	rake build
	cp ../../pkg/grpc-1.15.0.gem $CURDIR/
	printf -- 'Built grpc gem successfully\n'


	# Build gitaly-proto gem
	printf -- 'Building gitaly-proto gem \n'
	cd $CURDIR
	git clone https://gitlab.com/gitlab-org/gitaly-proto.git
	cd gitaly-proto/
	git checkout v1.5.0
	mkdir -p _build/protoc/bin
	cp /usr/bin/protoc _build/protoc/bin

	curl -o Makefile_gitlay_proto.diff $REPO_URL/Makefile_gitlay_proto.diff
	patch $CURDIR/gitaly-proto/Makefile Makefile_gitlay_proto.diff

	curl -o release.diff $REPO_URL/release.diff
	patch $CURDIR/gitaly-proto/_support/release release.diff
	cd $CURDIR/gitaly-proto/

	#make command will fail with error `Makefile:25: recipe for target 'generate' failed` due incompatible protoc binary.
	#Ignore the error and continue forward
	set +e
	make
	set -e
	#Rerun the build with correct protoc
	cp /usr/bin/protoc _build/protoc/bin
	mkdir -p /usr/local/lib/ruby/gems/2.5.0/gems/grpc-tools-1.0.1/bin/s390x-linux
	cp _build/bin/grpc_tools_ruby_protoc_plugin /usr/local/lib/ruby/gems/2.5.0/gems/grpc-tools-1.0.1/bin/s390x-linux
	cp _build/bin/protoc-gen-go /usr/local/lib/ruby/gems/2.5.0/gems/grpc-tools-1.0.1/bin/s390x-linux
	cp $CURDIR/grpc/bins/opt/grpc_ruby_plugin /usr/local/lib/ruby/gems/2.5.0/gems/grpc-tools-1.0.1/bin/s390x-linux
	cp /usr/bin/protoc /usr/local/lib/ruby/gems/2.5.0/gems/grpc-tools-1.0.1/bin/s390x-linux
	cp -r /usr/local/lib/ruby/gems/2.5.0/gems/grpc-tools-1.0.1/bin/x86_64-linux/google /usr/local/lib/ruby/gems/2.5.0/gems/grpc-tools-1.0.1/bin/s390x-linux
	make
	echo "Yes" | make release version=1.5.0
	cp gitaly-proto-1.5.0.gem $CURDIR/
	printf -- 'Built gitaly-proto gem successfully\n'

	#Build GitLab-CE

	#Fetch the source
	printf -- 'Fetching GitLab source\n'
	cd /home/git/
	sudo -u git -H git clone https://gitlab.com/gitlab-org/gitlab-ce.git -b 11-7-stable gitlab

	# Configure GitLab
	# Go to GitLab installation folder
	printf -- 'Configuring GitLab\n'
	cd /home/git/gitlab
	# Copy the example GitLab config
	sudo -u git -H cp config/gitlab.yml.example config/gitlab.yml

	curl -o gitlab.yml.diff $REPO_URL/gitlab.yml.diff
	patch /home/git/gitlab/config/gitlab.yml gitlab.yml.diff

	# Copy the example secrets file
	sudo -u git -H cp config/secrets.yml.example config/secrets.yml
	sudo -u git -H chmod 0600 config/secrets.yml

	# Make sure GitLab can write to the log/ and tmp/ directories
	chown -R git log/
	chown -R git tmp/
	chmod -R u+rwX,go-w log/
	chmod -R u+rwX tmp/

	# Make sure GitLab can write to the tmp/pids/ and tmp/sockets/ directories
	chmod -R u+rwX tmp/pids/
	chmod -R u+rwX tmp/sockets/

	# Create the public/uploads/ directory
	sudo -u git -H mkdir public/uploads/

	# Make sure only the GitLab user has access to the public/uploads/ directory
	# now that files in public/uploads are served by gitlab-workhorse
	chmod 0700 public/uploads

	# Change the permissions of the directory where CI job traces are stored
	chmod -R u+rwX builds/

	# Change the permissions of the directory where CI artifacts are stored
	chmod -R u+rwX shared/artifacts/

	# Change the permissions of the directory where GitLab Pages are stored
	chmod -R ug+rwX shared/pages/

	# Copy the example Unicorn config
	sudo -u git -H cp config/unicorn.rb.example config/unicorn.rb

	# Find number of cores
	# Enable cluster mode if you expect to have a high load instance
	# Set the number of workers to at least the number of cores
	# Ex. change amount of workers to 3 for 2GB RAM server
	sed -i "25s/.*/worker_processes ${NC}/" config/unicorn.rb

	# Copy the example Rack attack config
	sudo -u git -H cp config/initializers/rack_attack.rb.example config/initializers/rack_attack.rb

	# Configure Git global settings for git user
	# 'autocrlf' is needed for the web editor
	sudo -u git -H git config --global core.autocrlf input

	# Disable 'git gc --auto' because GitLab already runs 'git gc' when needed
	sudo -u git -H git config --global gc.auto 0

	# Enable packfile bitmaps
	sudo -u git -H git config --global repack.writeBitmaps true

	# Enable push options
	sudo -u git -H git config --global receive.advertisePushOptions true

	# Configure Redis connection settings
	sudo -u git -H cp config/resque.yml.example config/resque.yml

	#Configure GitLab DB Settings
	printf -- 'Configuring GitLab DB Settings\n'
	sudo -u git cp config/database.yml.postgresql config/database.yml
	# Update username/password in config/database.yml.
	# You only need to adapt the production settings (first part).
	# If you followed the database guide then please do as follows:
	# Change 'secure password' with the value you have given to $password
	# You can keep the double quotes around the password
	sed -i "10s/secure password//" config/database.yml

	sudo -u git -H chmod o-rwx config/database.yml

	#Install gems
	curl -o Gemfile_comment.diff $REPO_URL/Gemfile_comment.diff
	patch /home/git/gitlab/Gemfile Gemfile_comment.diff

	bundle install --no-deployment --without development test mysql aws kerberos
	cp /usr/local/lib/ruby/gems/2.5.0/cache/* $CURDIR/GEMREPO/repo/gems/
	cp $CURDIR/gitaly-proto-1.5.0.gem $CURDIR/GEMREPO/repo/gems/
	cp $CURDIR/google-protobuf-3.6.1.gem $CURDIR/GEMREPO/repo/gems/
	cp $CURDIR/grpc-1.15.0.gem $CURDIR/GEMREPO/repo/gems/
	cd $CURDIR/GEMREPO/repo
	gem generate_index
	cd /home/git/gitlab

	curl -o Gemfile_uncomment.diff $REPO_URL/Gemfile_uncomment.diff
	patch /home/git/gitlab/Gemfile Gemfile_uncomment.diff

	sed -i "s|https://rubygems.org|file:${CURDIR}/GEMREPO/repo|" /home/git/gitlab/Gemfile
	bundle install --no-deployment --without development test mysql aws kerberos
	sudo chown -R git:git /home/git/gitlab/.bundle
	sudo chmod -R u+rwX /home/git/gitlab/.bundle
	sudo -u git -H bundle install --no-deployment --without development test mysql aws kerberos

	# Install GitLab Shell
	printf -- 'Installing GitLab Shell\n'
	sudo -u git -H bundle exec rake gitlab:shell:install REDIS_URL=unix:/var/run/redis/redis.sock RAILS_ENV=production SKIP_STORAGE_VALIDATION=true

	# Install gitlab-workhorse
	printf -- 'Installing gitlab-workhorse\n'
	bundle exec rake "gitlab:workhorse:install[/home/git/gitlab-workhorse]" RAILS_ENV=production

	# Install gitlab-pages
	printf -- 'Installing gitlab-pages\n'
	cd /home/git
	sudo -u git -H git clone https://gitlab.com/gitlab-org/gitlab-pages.git
	cd gitlab-pages
	sudo -u git -H git checkout v$(</home/git/gitlab/GITLAB_PAGES_VERSION)
	sudo -u git -H make

	# Install Gitaly
	printf -- 'Gitaly installation started\n'
	cd /home/git/gitlab
	#expected to fail
	set +e
	sudo -u git -H bundle exec rake "gitlab:gitaly:install[/home/git/gitaly,/home/git/repositories]" RAILS_ENV=production
	set -e
	curl -o gitaly.rake.diff $REPO_URL/gitaly.rake.diff
	patch /home/git/gitlab/lib/tasks/gitlab/gitaly.rake gitaly.rake.diff

	curl -o Gemfile_gitaly_comment.diff $REPO_URL/Gemfile_gitaly_comment.diff
	patch /home/git/gitaly/_build/src/gitlab.com/gitlab-org/gitaly/ruby/Gemfile Gemfile_gitaly_comment.diff

	curl -o Gemfile.lock.diff $REPO_URL/Gemfile.lock.diff
	patch /home/git/gitaly/_build/src/gitlab.com/gitlab-org/gitaly/ruby/Gemfile.lock Gemfile.lock.diff

	cd /home/git/gitaly/_build/src/gitlab.com/gitlab-org/gitaly/ruby
	cp /home/git/gitaly/ruby/vendor/bundle/ruby/2.5.0/cache/* $CURDIR/GEMREPO/repo/gems/
	bundle install --no-deployment
	cp /usr/local/lib/ruby/gems/2.5.0/cache/* $CURDIR/GEMREPO/repo/gems/
	cp $CURDIR/gitaly-proto-1.5.0.gem $CURDIR/GEMREPO/repo/gems/
	cp $CURDIR/google-protobuf-3.6.1.gem $CURDIR/GEMREPO/repo/gems/
	cp $CURDIR/grpc-1.15.0.gem $CURDIR/GEMREPO/repo/gems/
	cd $CURDIR/GEMREPO/repo
	gem generate_index

	cd $CURDIR
	curl -o Gemfile_gitaly_uncomment.diff $REPO_URL/Gemfile_gitaly_uncomment.diff
	patch /home/git/gitaly/_build/src/gitlab.com/gitlab-org/gitaly/ruby/Gemfile Gemfile_gitaly_uncomment.diff

	curl -o Makefile_gitaly.diff $REPO_URL/Makefile_gitaly.diff
	patch /home/git/gitaly/_build/Makefile Makefile_gitaly.diff

	curl -o makegen.go.diff $REPO_URL/makegen.go.diff
	patch /home/git/gitaly/_support/makegen.go makegen.go.diff

	#Install Gitaly
	cd /home/git/gitaly/
	go build -o _build/makegen _support/makegen.go
	cd /home/git/gitaly/_build/src/gitlab.com/gitlab-org/gitaly/ruby
	sed -i "s|https://rubygems.org|file:${CURDIR}/GEMREPO/repo|" Gemfile
	bundle install --no-deployment
	cd /home/git/gitlab
	sudo -u git -H bundle exec rake "gitlab:gitaly:install[/home/git/gitaly,/home/git/repositories]" RAILS_ENV=production
	chmod 0700 /home/git/gitlab/tmp/sockets/private
	chown git /home/git/gitlab/tmp/sockets/private
	printf -- 'Installed Gitaly successfully\n'

	# Initialize Database and Activate Advanced Features
	printf -- 'Initializing Database and Activate Advanced Features\n'
	curl -o setup.rake.diff $REPO_URL/setup.rake.diff
	patch /home/git/gitlab/lib/tasks/gitlab/setup.rake setup.rake.diff
	echo "yes" | sudo -u git -H bundle exec rake gitlab:setup RAILS_ENV=production

	#Install Init Script
	cd /home/git/gitlab
	cp lib/support/init.d/gitlab /etc/init.d/gitlab
	#Make GitLab start on boot:
	sudo update-rc.d gitlab defaults 21
	#Set up Logrotate
	cp lib/support/logrotate/gitlab /etc/logrotate.d/gitlab

	#Check Application Status
	printf -- 'Verifying GitLab installation\n'
	sudo -u git -H bundle exec rake gitlab:env:info RAILS_ENV=production
	#Compile GetText PO files
	sudo -u git -H bundle exec rake gettext:compile RAILS_ENV=production
	#Compile Assets
	sudo -u git -H /usr/local/yarn-v1.13.0/bin/yarn install --production --pure-lockfile
	#Setting PATH again to find yarn binaries
	export PATH=/usr/local/yarn-v1.13.0/bin:/usr/local/node-v8.11.4-linux-s390x/bin:$PATH
	sudo -E PATH=$PATH -u git -H bundle exec rake gitlab:assets:compile RAILS_ENV=production NODE_ENV=production


	printf -- 'Starting GitLab instance\n'
	service gitlab start
	
	#Set up Nginx server
	printf -- 'Setting up Nginx server\n'
	cp lib/support/nginx/gitlab /etc/nginx/sites-available/gitlab
	ln -s /etc/nginx/sites-available/gitlab /etc/nginx/sites-enabled/gitlab
	# Edit 'listen 0.0.0.0:8234 default_server;' and 'listen [::]:8234 default_server;
	sed -i '69,70{s/80/8234/}' /etc/nginx/sites-available/gitlab 
	nginx -t
	sudo service nginx restart

	#verify the installation
	sudo -u git -H bundle exec rake gitlab:check RAILS_ENV=production
	printf -- 'Installtion is verified successfully\n'

	printenv >>"$LOG_FILE"
	printf -- 'Built GitLab successfully \n\n'
}

function logDetails() {
	printf -- 'SYSTEM DETAILS\n' >"$LOG_FILE"
	if [ -f "/etc/os-release" ]; then
		cat "/etc/os-release" >>"$LOG_FILE"
	fi

	cat /proc/version >>"$LOG_FILE"
	printf -- "\nDetected %s \n" "$PRETTY_NAME"
	printf -- "Request details : PACKAGE NAME= %s , VERSION= %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" |& tee -a "$LOG_FILE"
}

# Print the usage message
function printHelp() {
	echo
	echo "Usage: "
	echo "  install.sh  [-d debug] [-y install-without-confirmation]"
	echo
}


while getopts "h?dy" opt; do
	case "$opt" in
	h | \?)
		printHelp
		exit 0
		;;
	d)
		set -x
		;;
	y)
		FORCE="true"
		;;
	esac
done

function printSummary() {

	printf -- "\n* Getting Started * \n"
	printf -- '\nServer is listening on port 8234. Edit file /etc/nginx/sites-enabled/gitlab to change the port'
	printf -- "\nNote : Also change /home/git/gitlab/config/gitlab.yml to match the setup \n"
	printf -- "\nRefer build instructions for more information\n"
}

logDetails
prepare

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
	"ubuntu-18.04")
		printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
		printf -- '\nInstalling dependencies \n' |& tee -a "$LOG_FILE"
		apt-get update
		export DEBIAN_FRONTEND=noninteractive  
		apt-get install -y sudo vim build-essential zlib1g-dev libyaml-dev libssl-dev libgdbm-dev libre2-dev libreadline-dev libncurses5-dev libffi-dev curl openssh-server checkinstall libxml2-dev libxslt-dev libcurl4-openssl-dev libicu-dev logrotate rsync python-docutils pkg-config gettext cmake libcurl4-openssl-dev libexpat1-dev gettext libz-dev libssl-dev build-essential curl wget autoconf postgresql postgresql-client libpq-dev postgresql-contrib redis-server autoconf libtool libgoogle-perftools-dev protobuf-compiler unzip nodejs nginx
		dependencyInstall |& tee -a "$LOG_FILE"
		configureAndInstall |& tee -a "$LOG_FILE"
		;;

	*)
		printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
		exit 1
		;;
esac

# Print Summary
printSummary |& tee -a "$LOG_FILE"
