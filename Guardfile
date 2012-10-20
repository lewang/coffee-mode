require 'guard/guard'

# Install the guard gem and then run "guard" command  from the project root

module ::Guard
  class Emacs < ::Guard::Guard
    def run_all
      system "make travis-ci"
    end

    def start
      run_all
    end

    def run_on_changes(paths)
      run_all
    end

    def reload
      run_all
    end
  end
end

guard 'emacs', {
  :wait => 5,
} do
  watch(%r{\.el\Z})
end
