module DariusRoberts
    module FindRandom #:nodoc:

      def self.included(base)
        ActiveRecord::Associations::ClassMethods.extend DariusRoberts::FindRandom::AssocIdFind
        base.extend DariusRoberts::FindRandom::IdFind
        base.extend DariusRoberts::FindRandom::FindRandomSingleton
      end

      module AssocIdFind
        def find_with_associations_ids(options = {})
          catch :invalid_query do
            join_dependency = JoinDependency.new(self, merge_includes(scope(:find, :include), options[:include]), options[:joins])
            logger.debug("All rows: " + select_all_rows(options, join_dependency).inspect)
            return select_all_rows(options, join_dependency).collect { |row| row[join_dependency.joins.first.aliased_primary_key] }
          end
          []
        end
      end

      module IdFind
        def find_ids(*args)
          options = args.extract_options!
          logger.debug("Find by ID:" + options.inspect)
          validate_find_options(options)      

          case args.first
            when :first then find_initial_id(options)
            when :all   then find_every_id(options)
          end
        end  

        def find_by_sql_ids(sql)
          connection.select_all(sanitize_sql(sql), "#{name} Load").collect! { |record| record['id'] }
        end    

        private

        def find_initial_id(options)
          options.update(:limit => 1) unless options[:include]
          find_every_id(options).first
        end

        def find_every_id(options)
          records = scoped?(:find, :include) || options[:include] ?
            find_with_associations_ids(options) : 
            find_by_sql_ids(construct_finder_sql(options))
          records
        end

      end

      module FindRandomSingleton
        def filter_ids(ids, options)
           conditions = " AND (#{sanitize_sql(options[:conditions])})" if options[:conditions]
           ids_list   = ids.map { |id| quote_value(id,columns_hash[primary_key]) }.join(',')
           options.update :conditions => "#{quoted_table_name}.#{connection.quote_column_name(primary_key)} IN (#{ids_list})#{conditions}"

           return [] if ids.blank?
           # else
           result = find_every_id(options)

           # but wait! need to re-expand the filtered ids -- duplicate ids ARE acceptable.
           non_uniq_ids = ids.group_by(&:to_i)
           result.inject([]) {|i,r| i += non_uniq_ids.assoc(r.to_i).last } 
         end

         def find_random(*args)       
           options = args.extract_options!
           validate_find_options(options)
           set_readonly_option!(options)

           return find_random(:first, options) if args.blank?
           ids = case args.first
           when :first; return [find_by_id( find_every_id(options).rand )]
           when :all; find_every_id(options)
           when Array; args.first
           when Hash; args.first.inject([]) {|i,(k,v)| (v * 100).round.times { i << k}; i } # values taken as weighting. Only works to 2 digits.
           when Integer; return find_random(:all,options.merge(:limit=>args.first))
           else; ArgumentError "Hmmm. What are you feeding find_random? It eats shoots and leaves." 
           end

           limit = options.delete(:limit)    || 1              
           ids  =  Array self.filter_ids(ids, options)

           return [] if ids.blank?
           find (1..limit).map { ids.delete_at( ids.size * rand ) } 
         end
      end
    end
end
