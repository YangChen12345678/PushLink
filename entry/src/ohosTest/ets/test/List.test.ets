import abilityTest from './Ability.test';
import pipelineTest from './Pipeline.test';
import storageTest from './Storage.test';

export default function testsuite() {
  abilityTest();
  pipelineTest();
  storageTest();
}
