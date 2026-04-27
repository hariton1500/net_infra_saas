class AppStrings {
  const AppStrings._();

  static const appTitle = 'Net Infra SaaS';

  static const signIn = 'Sign in';
  static const signUp = 'Sign up';
  static const signOut = 'Sign out';
  static const signOutOfAccount = 'Sign out of account';
  static const retry = 'Retry';
  static const cancel = 'Cancel';
  static const save = 'Save';
  static const create = 'Create';
  static const delete = 'Delete';
  static const edit = 'Edit';
  static const close = 'Close';
  static const open = 'Open';
  static const refresh = 'Refresh';
  static const profile = 'Profile';
  static const company = 'Company';
  static const employee = 'Employee';
  static const owner = 'Owner';
  static const administrator = 'Administrator';
  static const engineer = 'Engineer';
  static const chiefEngineer = 'Chief Engineer';
  static const installer = 'Installer';

  static const setupSupabaseTitle = 'Supabase is not configured yet';
  static const setupSupabaseBody =
      'Before launching the app, pass two dart-define values to the project: SUPABASE_URL and SUPABASE_ANON_KEY.';
  static const setupSupabaseAfter =
      'After that, the app will show the sign-in screen and company onboarding.';

  static const authHeroTitle =
      'Infrastructure management for companies and their teams';
  static const authHeroBody =
      'Access the company workspace, create the first organization, and prepare employee access on one shared platform.';
  static const oneAccountPerCompany = 'One account per company';
  static const oneAccountPerCompanyBody =
      'The owner creates the workspace and then adds employees.';
  static const supabaseSessions = 'Supabase sessions';
  static const supabaseSessionsBody =
      'The app automatically restores the active user session.';
  static const readyForMultiTenant = 'Ready for multi-tenant';
  static const readyForMultiTenantBody =
      'Profiles, companies, and employee roles are already isolated at the database level.';

  static const employeeSignIn = 'Employee sign in';
  static const employeeSignInBody =
      'Use your work email and password to open the company workspace.';
  static const companyOwnerSignUp = 'Company owner registration';
  static const companyOwnerSignUpBody =
      'Create the first company account. After that, you can add employees.';
  static const restorePassword = 'Reset password';
  static const restorePasswordBody =
      'Enter your work email. We will send a message with a link to change your password.';
  static const sendEmail = 'Send email';
  static const workEmail = 'Work email';
  static const password = 'Password';
  static const newPassword = 'New password';
  static const repeatNewPassword = 'Repeat new password';
  static const saveNewPassword = 'Save new password';
  static const leaveRecoveryMode = 'Leave recovery mode';
  static const setNewPassword = 'Set a new password';
  static const setNewPasswordBody =
      'We confirmed the recovery link. You can now set a new password for the account.';
  static const yourName = 'Your name';
  static const position = 'Position';
  static const companyName = 'Company name';
  static const goToSignIn = 'Go to sign in';
  static const createCompany = 'Create company';

  static const completeCompanySetup = 'Complete company setup';
  static const completeCompanySetupBody =
      'You are signed in as {email}, but the company workspace has not been created yet.';
  static const createWorkspace = 'Create workspace';
  static const user = 'User';

  static const employeeProfile = 'Employee profile';
  static const personalDetails = 'Personal details';
  static const personalDetailsBody =
      'Here you can update the name and position. Email and role are read-only.';
  static const companyRole = 'Company role';
  static const employeeName = 'Employee name';
  static const saveProfile = 'Save profile';
  static const profileUpdated = 'Profile updated.';

  static const dataLoadProblem = 'There is a problem loading data';
  static const sessionLoadFailed = 'Failed to load session.';
  static const genericError = 'Something went wrong.';
  static const signInFailed = 'Failed to sign in.';
  static const signUpFailed = 'Failed to create the account.';
  static const passwordUpdateFailed = 'Failed to update the password.';
  static const recoveryEmailFailed =
      'Failed to send the password recovery email.';
  static const companySetupFailed = 'Failed to complete company setup.';
  static const inviteCreateFailed = 'Failed to create the invite.';
  static const dataRefreshFailed = 'Failed to refresh the data.';
  static const profileUpdateFailed = 'Failed to update the profile.';
  static const createCompanyNameRequired = 'Please enter a company name.';
  static const fieldRequired = 'This field is required.';
  static const enterEmail = 'Enter an email address.';
  static const enterValidEmail = 'Enter a valid email address.';
  static const enterPassword = 'Enter a password.';
  static const enterNewPassword = 'Enter a new password.';
  static const minEightCharacters = 'Minimum 8 characters.';
  static const passwordsDoNotMatch = 'Passwords do not match.';
  static const enterEmployeeName = 'Enter the employee name.';
  static const accountCreatedConfirmEmail =
      'The account has been created. Confirm your email and then sign in.';
  static const companyCreatedContinue =
      'The company has been created. You can continue working.';
  static const companyLinkedAccountReady =
      'The company is connected and the account is ready.';
  static const inviteCreated = 'Invite created.';
  static const inviteCreatedWithCode = 'Invite created. Invite code: {token}';
  static const resetEmailRequired =
      'Enter the email address for password recovery.';
  static const resetEmailSent =
      'We sent a password recovery email if an account with this address exists.';
  static const passwordUpdated = 'Password updated.';
  static const duplicateEmail =
      'An account with this email already exists. Try signing in or resetting the password.';
  static const duplicateEmailSignIn =
      'An account with this email already exists. Go to sign in or reset the password.';

  static const dashboardSignedInAs = 'You are signed in as {name}.';
  static const dashboardRole = 'Company role: {role}';
  static const dashboardSlug = 'Company slug: {slug}';
  static const employees = 'Employees';
  static const invites = 'Invites';
  static const activeTeamMembers = 'Active team members';
  static const awaitingAcceptance = 'Awaiting acceptance';
  static const emailValue = 'Email: {value}';
  static const positionValue = 'Position: {value}';
  static const nameValue = 'Name: {value}';
  static const titleValue = 'Title: {value}';
  static const roleValue = 'Role: {value}';
  static const belowYouCanInvite =
      'Below you can invite employees by email.';
  static const membershipAutoConnect =
      'If the employee registers with this email, the membership will be attached automatically.';
  static const teamAndPendingInvitesVisible =
      'The team list and pending invites are available for viewing.';
  static const inviteCreationAvailable =
      'Creating invites is available to owners and administrators.';
  static const inviteEmployee = 'Invite employee';
  static const inviteEmployeeBody =
      'Create an invite using a work email. The employee will register with this email and automatically join the company.';
  static const employeeEmail = 'Employee email';
  static const sendInvite = 'Send invite';
  static const companyTeam = 'Company team';
  static const noEmployeesYet = 'There are no employees yet.';
  static const pendingInvites = 'Pending invites';
  static const noActiveInvites = 'There are no active invites.';
  static const inviteCodeDate = 'Code: {token} - {date}';
  static const idValue = 'ID: {value}';
  static const defaultPositionNotice =
      'Only the company owner can assign a position. Employees will use the default position by default.';

  static String lookup(String key) => key;
}
