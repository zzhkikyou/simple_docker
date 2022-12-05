.PHONY:shc
shc:
	@mkdir -p bin
	@cp simple_docker.sh bin/
	@shc -v -r -f bin/simple_docker.sh
	@mv bin/simple_docker.sh.x bin/simple_docker

.PHONY:gzexe
gzexe:
	@mkdir -p bin
	@cp simple_docker.sh bin/
	@gzexe bin/simple_docker.sh
	@mv bin/simple_docker.sh bin/simple_docker
	@chmod +x bin/simple_docker

.PHONY:clean
clean:
	@mkdir -p bin
	@rm -rf bin/*