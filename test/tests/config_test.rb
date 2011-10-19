
context "a config object" do

  asserts("given an yaml structure") {Amatsung::Config.new(": :")}.raises(Amatsung::InvalidConfig)
  asserts("given an invalid yaml file") {Amatsung::Config.new(open('test/testfiles/testconfig-invalid.yml'))}.raises(Amatsung::InvalidConfig)
  asserts("given a valid yaml file") {Amatsung::Config.new(open('test/testfiles/testconfig-valid.yml'))}

  context "> given a structurally sound yaml file with errors" do

    context "> unsuported cloud provider" do
      setup do
        Amatsung::Config.new(open('test/testfiles/testconfig-unsupported-provider.yml'))
      end

      denies(:valid?)
      asserts(:errors).equals({:provider => "Provider 'Unsupported' is not a supported provider."})

    end

    context "> missing cloud credentials" do

    end

  end

end