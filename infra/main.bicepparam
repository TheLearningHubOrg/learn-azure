using './main.bicep'

param namePrefix = 'learnaz'
param environment = 'dev'
param maximumInstanceCount = 40
param tags = {
  project: 'learn-azure'
  environment: 'dev'
  costCenter: 'training'
}
