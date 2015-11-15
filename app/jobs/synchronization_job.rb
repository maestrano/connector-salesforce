class SynchronizationJob
  EXTERNAL_NAME = "SalesForce"

  # Supported options:
  #  * :only_entities => [person, tasks_list]
  #  * :full_sync => true  synchronization is performed without date filtering
  #  * :force_sync_connec => true  Force a fetching of Connec! data (usually only done for the first sync, subsequents syncs are done via webhooks)
  #  * :external_preemption => true  preemption is given to external instead of connec! is case of conflict. Usefull only is synchronization is performed to both connec! and external
  def sync(organization, opts={})
    Rails.logger.info "Start synchronization, organization=#{organization.uid}"
    current_synchronization = Synchronization.create(organization_id: organization.id, status: 'RUNNING')

    begin
      last_synchronization = Synchronization.where(organization_id: organization.id, status: 'SUCCESS', partial: false).order(updated_at: :desc).first
      connec_client = Maestrano::Connec::Client.new(organization.uid)
      external_client = Restforce.new :oauth_token => organization.oauth_token,
        refresh_token: organization.refresh_token,
        instance_url: organization.instance_url,
        client_id: ENV['salesforce_client_id'],
        client_secret: ENV['salesforce_client_secret']

      if opts[:only_entities]
        # The synchronization is marked as partial and will not be considered as the last-synchronization for the next sync
        current_synchronization.update_attributes(partial: true)
        opts[:only_entities].each do |entity|
          sync_entity(entity, organization, connec_client, external_client, last_synchronization, opts)
        end
      else
        organization.synchronized_entities.select{|k, v| v}.keys.each do |entity|
          sync_entity(entity.to_s, organization, connec_client, external_client, last_synchronization, opts)
        end
      end

      Rails.logger.info "Finished synchronization, organization=#{organization.uid}, status=success"
      current_synchronization.update_attributes(status: 'SUCCESS')
    rescue => e
      Rails.logger.info "Finished synchronization, organization=#{organization.uid}, status=error, message=#{e.message} backtrace=#{e.backtrace.join("\n\t")}"
      current_synchronization.update_attributes(status: 'ERROR', message: e.message)
    end
  end

  private
    def sync_entity(entity, organization, connec_client, external_client, last_synchronization, opts)
      entity_class = "Entities::#{entity.titleize.split.join}".constantize.new
      entity_class.set_mapper_organization(organization.id)

      external_entities = entity_class.get_external_entities(external_client, last_synchronization, opts)

      if last_synchronization.blank? || opts[:force_sync_connec]
        connec_entities = entity_class.get_connec_entities(connec_client, last_synchronization, opts)
        entity_class.consolidate_and_map_data(connec_entities, external_entities, organization, opts)
        entity_class.push_entities_to_external(external_client, connec_entities, organization)
      else
        entity_class.map_external_entities(external_entities)
      end

      entity_class.push_entities_to_connec(connec_client, external_entities, organization)

      entity_class.unset_mapper_organization
    end
end