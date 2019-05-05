Summary:
Name:
Version:
Release:
SOURCE0 : %{name}-%{version}.tar.gz
BuildArch: x86_64
BuildRoot: %{_tmppath}/%{name}-%{version}
License:
Requires:


# define some path here
%define



%description
%{summary}

%prep
%setup -q

%build

%install


%post

%preun

%postun

%clean
rm -rf %{buildroot}

%files

# change it by your requirements
%defattr(-,root,root,-)


%{TARGET_DIR}

%changelog