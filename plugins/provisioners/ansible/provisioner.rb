module VagrantPlugins
  module Ansible
    class Provisioner < Vagrant.plugin("2", :provisioner)
      def provision
        ssh = @machine.ssh_info
        inventory_file_path = self.setup_inventory_file
        options = %W[--private-key=#{ssh[:private_key_path]} --user=#{ssh[:username]}]
        options << "--inventory-file=#{inventory_file_path}"
        options << "--ask-sudo-pass" if config.ask_sudo_pass

        if config.extra_vars
          extra_vars = config.extra_vars.map do |k,v|
            v = v.gsub('"', '\\"')
            if v.include?(' ')
              v = v.gsub("'", "\\'")
              v = "'#{v}'"
            end

            "#{k}=#{v}"
          end

          options << "--extra-vars=\"#{extra_vars.join(" ")}\""
        end

        if config.limit
          if not config.limit.kind_of?(Array)
            config.limit = [config.limit]
          end
          config.limit = config.limit.join(",")
          options << "--limit=#{config.limit}"
        end

        options << "--sudo" if config.sudo
        options << "--sudo-user=#{config.sudo_user}" if config.sudo_user
        if config.verbose
          options << (config.verbose.to_s == "extra" ?  "-vvv" :  "--verbose")
        end

        # Assemble the full ansible-playbook command
        command = (%w(ansible-playbook) << options << config.playbook).flatten

        # Write stdout and stderr data, since it's the regular Ansible output
        command << {
          :env => { "ANSIBLE_FORCE_COLOR" => "true" },
          :notify => [:stdout, :stderr],
          :workdir => @machine.env.root_path.to_s
        }

        begin
          result = Vagrant::Util::Subprocess.execute(*command) do |type, data|
            if type == :stdout || type == :stderr
              @machine.env.ui.info(data, :new_line => false, :prefix => false)
            end
          end

          raise Vagrant::Errors::AnsibleFailed if result.exit_code != 0
        rescue Vagrant::Util::Subprocess::LaunchError
          raise Vagrant::Errors::AnsiblePlaybookAppNotFound
        end
      end

      def setup_inventory_file
        return config.inventory_path if config.inventory_path

        ssh = @machine.ssh_info

        generated_inventory_file =
          @machine.env.root_path.join("vagrant_ansible_inventory_#{machine.name}")

        generated_inventory_file.open('w') do |file|
          file.write("# Generated by Vagrant\n\n")
          file.write("#{machine.name} ansible_ssh_host=#{ssh[:host]} ansible_ssh_port=#{ssh[:port]}\n")
        end

        return generated_inventory_file.to_s
      end
    end
  end
end
